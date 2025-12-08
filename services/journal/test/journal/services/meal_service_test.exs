defmodule Journal.Services.MealServiceTest do
  use ExUnit.Case, async: true
  use Journal.DataCase

  # Tests that use LLM mocks should not run in parallel to avoid race conditions
  @moduletag :llm_mock

  alias Journal.Services.MealService
  alias Journal.TestHelpers.LLMHelpers
  alias JournalWeb.MealHelpers

  describe "create_meal/2" do
    test "creates meal with valid attributes" do
      attrs = %{
        meal_type: :breakfast,
        original_description: "Oatmeal with berries"
      }

      assert {:ok, meal} = MealService.create_meal(1, attrs)
      assert meal.patient_id == 1
      assert meal.meal_type == :breakfast
      assert meal.original_description == "Oatmeal with berries"
      assert meal.status == :pending
      assert meal.date == Date.utc_today()
    end

    test "creates meal with atom keys in attrs" do
      attrs = %{
        meal_type: :lunch,
        original_description: "Grilled chicken salad"
      }

      assert {:ok, meal} = MealService.create_meal(1, attrs)
      assert meal.meal_type == :lunch
    end

    test "creates meal with string keys in attrs" do
      attrs = %{
        "meal_type" => :dinner,
        "original_description" => "Salmon with vegetables"
      }

      assert {:ok, meal} = MealService.create_meal(1, attrs)
      assert meal.meal_type == :dinner
    end

    test "defaults date to today when not provided" do
      attrs = %{
        meal_type: :breakfast,
        original_description: "2 eggs"
      }

      assert {:ok, meal} = MealService.create_meal(1, attrs)
      assert meal.date == Date.utc_today()
    end

    test "parses ISO8601 date strings" do
      date = ~D[2024-01-15]
      attrs = %{
        meal_type: :lunch,
        original_description: "Salad",
        date: "2024-01-15"
      }

      assert {:ok, meal} = MealService.create_meal(1, attrs)
      assert meal.date == date
    end

    test "accepts Date struct directly" do
      date = ~D[2024-01-15]
      attrs = %{
        meal_type: :dinner,
        original_description: "Steak",
        date: date
      }

      assert {:ok, meal} = MealService.create_meal(1, attrs)
      assert meal.date == date
    end

    test "removes invalid date strings and defaults to today" do
      attrs = %{
        meal_type: :breakfast,
        original_description: "Toast",
        date: "invalid-date"
      }

      assert {:ok, meal} = MealService.create_meal(1, attrs)
      assert meal.date == Date.utc_today()
    end

    test "returns error when required fields are missing" do
      attrs = %{}

      assert {:error, changeset} = MealService.create_meal(1, attrs)
      refute changeset.valid?
      assert %{meal_type: [_], original_description: [_]} = errors_on(changeset)
    end

    test "returns error when original_description is empty" do
      attrs = %{
        meal_type: :breakfast,
        original_description: ""
      }

      assert {:error, changeset} = MealService.create_meal(1, attrs)
      refute changeset.valid?
      assert %{original_description: [_]} = errors_on(changeset)
    end

    test "handles non-map input gracefully" do
      # This should not crash, but will log a warning
      assert {:error, changeset} = MealService.create_meal(1, nil)
      refute changeset.valid?
    end
  end

  describe "start_processing/1" do
    test "transitions meal from pending to processing" do
      {:ok, meal} = MealHelpers.create_meal(%{
        meal_type: :breakfast,
        original_description: "Oatmeal",
        status: :pending
      })

      assert {:ok, updated_meal} = MealService.start_processing(meal)
      assert updated_meal.status == :processing
      assert updated_meal.id == meal.id
    end

    test "returns error when meal is not in pending status" do
      {:ok, meal} = MealHelpers.create_meal(%{
        meal_type: :breakfast,
        original_description: "Oatmeal",
        status: :in_review
      })

      assert {:error, {:invalid_status, :in_review, expected: :pending}} =
               MealService.start_processing(meal)
    end

    test "returns error for all non-pending statuses" do
      for status <- [:processing, :in_review, :confirmed] do
        {:ok, meal} = MealHelpers.create_meal(%{
          meal_type: :breakfast,
          original_description: "Oatmeal",
          status: status
        })

        assert {:error, {:invalid_status, ^status, expected: :pending}} =
                 MealService.start_processing(meal)
      end
    end
  end

  describe "process_with_llm/1" do
    test "successfully processes meal through full flow" do
      {:ok, meal} = MealHelpers.create_meal(%{
        meal_type: :breakfast,
        original_description: "2 eggs and toast",
        status: :pending
      })

      LLMHelpers.with_openai_mock(fn ->
        assert {:ok, processed_meal} = MealService.process_with_llm(meal)
        assert processed_meal.status == :in_review
        assert processed_meal.protein_g != nil
        assert processed_meal.carbs_g != nil
        assert processed_meal.fat_g != nil
        assert processed_meal.calories_kcal != nil
        assert processed_meal.weight_g != nil
        assert processed_meal.ai_comment != nil
      end)
    end

    test "returns error when meal is not in pending status" do
      {:ok, meal} = MealHelpers.create_meal(%{
        meal_type: :breakfast,
        original_description: "Oatmeal",
        status: :in_review
      })

      assert {:error, {:invalid_status, :in_review, expected: :pending}} =
               MealService.process_with_llm(meal)
    end

    test "returns error when LLM service fails" do
      {:ok, meal} = MealHelpers.create_meal(%{
        meal_type: :breakfast,
        original_description: "2 eggs and toast",
        status: :pending
      })

      LLMHelpers.with_openai_mock_error({:error, :timeout}, fn ->
        assert {:error, :timeout} = MealService.process_with_llm(meal)
      end)
    end

    test "returns error when OpenAI API key is not configured" do
      {:ok, meal} = MealHelpers.create_meal(%{
        meal_type: :breakfast,
        original_description: "2 eggs and toast",
        status: :pending
      })

      LLMHelpers.with_openai_not_configured(fn ->
        assert {:error, :api_key_not_configured} = MealService.process_with_llm(meal)
      end)
    end
  end

  describe "complete_processing/2" do
    test "transitions meal from processing to in_review with estimation" do
      {:ok, meal} = MealHelpers.create_meal(%{
        meal_type: :breakfast,
        original_description: "Oatmeal",
        status: :processing
      })

      estimation = %{
        protein_g: Decimal.new("25.5"),
        carbs_g: Decimal.new("30.0"),
        fat_g: Decimal.new("10.5"),
        calories_kcal: 300,
        weight_g: 250,
        ai_comment: "Balanced breakfast"
      }

      assert {:ok, updated_meal} = MealService.complete_processing(meal, estimation)
      assert updated_meal.status == :in_review
      assert Decimal.equal?(updated_meal.protein_g, Decimal.new("25.5"))
      assert updated_meal.calories_kcal == 300
      assert updated_meal.ai_comment == "Balanced breakfast"
    end

    test "returns error when meal is not in processing status" do
      {:ok, meal} = MealHelpers.create_meal(%{
        meal_type: :breakfast,
        original_description: "Oatmeal",
        status: :pending
      })

      estimation = %{protein_g: Decimal.new("25.0")}

      assert {:error, {:invalid_status, :pending, expected: :processing}} =
               MealService.complete_processing(meal, estimation)
    end

    test "returns error for all non-processing statuses" do
      estimation = %{protein_g: Decimal.new("25.0")}

      for status <- [:pending, :in_review, :confirmed] do
        {:ok, meal} = MealHelpers.create_meal(%{
          meal_type: :breakfast,
          original_description: "Oatmeal",
          status: status
        })

        assert {:error, {:invalid_status, ^status, expected: :processing}} =
                 MealService.complete_processing(meal, estimation)
      end
    end
  end

  describe "confirm_meal/1" do
    test "transitions meal from in_review to confirmed" do
      {:ok, meal} = MealHelpers.create_meal(%{
        meal_type: :breakfast,
        original_description: "Oatmeal",
        status: :in_review
      })

      assert {:ok, updated_meal} = MealService.confirm_meal(meal)
      assert updated_meal.status == :confirmed
      assert updated_meal.id == meal.id
    end

    test "returns error when meal is not in in_review status" do
      {:ok, meal} = MealHelpers.create_meal(%{
        meal_type: :breakfast,
        original_description: "Oatmeal",
        status: :pending
      })

      assert {:error, {:invalid_status, :pending, expected: :in_review}} =
               MealService.confirm_meal(meal)
    end

    test "returns error for all non-in_review statuses" do
      for status <- [:pending, :processing, :confirmed] do
        {:ok, meal} = MealHelpers.create_meal(%{
          meal_type: :breakfast,
          original_description: "Oatmeal",
          status: status
        })

        assert {:error, {:invalid_status, ^status, expected: :in_review}} =
                 MealService.confirm_meal(meal)
      end
    end
  end

  describe "override_values/2" do
    test "successfully overrides nutritional values" do
      {:ok, meal} = MealHelpers.create_meal(%{
        meal_type: :breakfast,
        original_description: "Oatmeal",
        protein_g: Decimal.new("20.0"),
        carbs_g: Decimal.new("30.0"),
        fat_g: Decimal.new("10.0"),
        calories_kcal: 250,
        weight_g: 200
      })

      attrs = %{
        "protein_g" => Decimal.new("25.0"),
        "carbs_g" => Decimal.new("35.0")
      }

      assert {:ok, updated_meal} = MealService.override_values(meal, attrs)
      assert Decimal.equal?(updated_meal.protein_g, Decimal.new("25.0"))
      assert Decimal.equal?(updated_meal.carbs_g, Decimal.new("35.0"))
      assert Decimal.equal?(updated_meal.fat_g, Decimal.new("10.0"))
      assert updated_meal.has_manual_override == true
      assert Map.has_key?(updated_meal.overridden_fields, "protein_g")
      assert Map.has_key?(updated_meal.overridden_fields, "carbs_g")
    end

    test "handles atom keys in attrs" do
      {:ok, meal} = MealHelpers.create_meal(%{
        meal_type: :breakfast,
        original_description: "Oatmeal",
        protein_g: Decimal.new("20.0")
      })

      attrs = %{protein_g: Decimal.new("25.0")}

      assert {:ok, updated_meal} = MealService.override_values(meal, attrs)
      assert Decimal.equal?(updated_meal.protein_g, Decimal.new("25.0"))
    end

    test "returns error when validation fails" do
      {:ok, meal} = MealHelpers.create_meal(%{
        meal_type: :breakfast,
        original_description: "Oatmeal"
      })

      # Negative values should fail validation
      attrs = %{protein_g: Decimal.new("-10.0")}

      assert {:error, changeset} = MealService.override_values(meal, attrs)
      refute changeset.valid?
    end
  end

  describe "list_meals/2" do
    setup do
      patient_id = MealHelpers.poc_patient_id()
      other_patient_id = 2

      # Create meals for patient 1 on 2024-01-15
      {:ok, meal1} = MealHelpers.create_meal(%{
        patient_id: patient_id,
        date: ~D[2024-01-15],
        meal_type: :breakfast,
        original_description: "Breakfast 1",
        status: :confirmed
      })

      {:ok, meal2} = MealHelpers.create_meal(%{
        patient_id: patient_id,
        date: ~D[2024-01-15],
        meal_type: :lunch,
        original_description: "Lunch 1",
        status: :in_review
      })

      # Create meal for patient 1 on different date
      {:ok, meal3} = MealHelpers.create_meal(%{
        patient_id: patient_id,
        date: ~D[2024-01-16],
        meal_type: :dinner,
        original_description: "Dinner 1",
        status: :pending
      })

      # Create meal for other patient on same date
      {:ok, _other_meal} = MealHelpers.create_meal(%{
        patient_id: other_patient_id,
        date: ~D[2024-01-15],
        meal_type: :breakfast,
        original_description: "Other patient meal",
        status: :confirmed
      })

      %{patient_id: patient_id, meal1: meal1, meal2: meal2, meal3: meal3}
    end

    test "lists meals for a patient on specific date", %{patient_id: patient_id, meal1: meal1, meal2: meal2} do
      meals = MealService.list_meals(patient_id, ~D[2024-01-15])
      assert length(meals) == 2
      assert Enum.all?(meals, fn m -> m.date == ~D[2024-01-15] end)
      assert Enum.all?(meals, fn m -> m.patient_id == patient_id end)
      # Verify both meals are present (order may vary due to timing)
      meal_ids = Enum.map(meals, & &1.id)
      assert meal1.id in meal_ids
      assert meal2.id in meal_ids
    end

    test "returns empty list when no meals match date", %{patient_id: patient_id} do
      meals = MealService.list_meals(patient_id, ~D[2024-01-20])
      assert meals == []
    end

    test "does not return meals for other patients", %{patient_id: patient_id} do
      meals = MealService.list_meals(patient_id, ~D[2024-01-15])
      assert Enum.all?(meals, fn m -> m.patient_id == patient_id end)
    end

    test "returns empty list for patient with no meals on date" do
      meals = MealService.list_meals(999, ~D[2024-01-15])
      assert meals == []
    end

    test "filters correctly for different dates", %{patient_id: patient_id, meal3: meal3} do
      meals_15 = MealService.list_meals(patient_id, ~D[2024-01-15])
      meals_16 = MealService.list_meals(patient_id, ~D[2024-01-16])

      assert length(meals_15) == 2
      assert length(meals_16) == 1
      assert Enum.at(meals_16, 0).id == meal3.id
    end
  end

  describe "get_meal/2" do
    test "returns meal when found and belongs to patient" do
      {:ok, meal} = MealHelpers.create_meal(%{
        meal_type: :breakfast,
        original_description: "Oatmeal"
      })

      assert {:ok, found_meal} = MealService.get_meal(MealHelpers.poc_patient_id(), meal.id)
      assert found_meal.id == meal.id
      assert found_meal.patient_id == MealHelpers.poc_patient_id()
    end

    test "returns error when meal is not found" do
      assert {:error, :not_found} = MealService.get_meal(MealHelpers.poc_patient_id(), MealHelpers.non_existent_id())
    end

    test "returns error when meal belongs to different patient" do
      {:ok, meal} = MealHelpers.create_meal(%{
        meal_type: :breakfast,
        original_description: "Oatmeal"
      })

      assert {:error, :not_found} = MealService.get_meal(2, meal.id)
    end
  end
end
