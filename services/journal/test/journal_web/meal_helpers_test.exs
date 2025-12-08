defmodule JournalWeb.MealHelpersTest do
  @moduledoc """
  Tests for MealHelpers test utilities.

  These tests ensure that the helper functions and macros work correctly
  for creating test data and asserting meal structures in tests.
  """
  use JournalWeb.ConnCase, async: true

  alias JournalWeb.MealHelpers

  require JournalWeb.MealHelpers

  describe "create_meal/1" do
    test "creates meal with default attributes" do
      {:ok, meal} = MealHelpers.create_meal()

      assert meal.patient_id == MealHelpers.poc_patient_id()
      assert meal.meal_type == :breakfast
      assert meal.original_description == "Test meal"
      assert meal.status == :pending
      assert %Date{} = meal.date
    end

    test "creates meal with custom attributes" do
      date = ~D[2025-01-27]
      {:ok, meal} = MealHelpers.create_meal(%{
        meal_type: :lunch,
        original_description: "Custom meal",
        status: :confirmed,
        date: date
      })

      assert meal.meal_type == :lunch
      assert meal.original_description == "Custom meal"
      assert meal.status == :confirmed
      assert meal.date == date
    end

    test "creates meal with partial overrides" do
      {:ok, meal} = MealHelpers.create_meal(%{status: :in_review})

      assert meal.patient_id == MealHelpers.poc_patient_id()
      assert meal.meal_type == :breakfast
      assert meal.status == :in_review
    end

    test "creates meal with snack meal type" do
      {:ok, meal} = MealHelpers.create_meal(%{meal_type: :snack})

      assert meal.meal_type == :snack
    end

    test "creates meal with dinner meal type" do
      {:ok, meal} = MealHelpers.create_meal(%{meal_type: :dinner})

      assert meal.meal_type == :dinner
    end

    test "creates meal with processing status" do
      {:ok, meal} = MealHelpers.create_meal(%{status: :processing})

      assert meal.status == :processing
    end

    test "creates meal with empty attrs map" do
      {:ok, meal} = MealHelpers.create_meal(%{})

      assert meal.patient_id == MealHelpers.poc_patient_id()
      assert meal.meal_type == :breakfast
    end
  end

  describe "create_meal_attrs/1" do
    test "creates attrs with defaults" do
      attrs = MealHelpers.create_meal_attrs()

      assert attrs["meal_type"] == "breakfast"
      assert attrs["original_description"] == "2 eggs and toast"
    end

    test "creates attrs with overrides" do
      attrs = MealHelpers.create_meal_attrs(%{
        "meal_type" => "lunch",
        "original_description" => "Grilled chicken"
      })

      assert attrs["meal_type"] == "lunch"
      assert attrs["original_description"] == "Grilled chicken"
    end

    test "creates attrs with partial overrides" do
      attrs = MealHelpers.create_meal_attrs(%{"meal_type" => "dinner"})

      assert attrs["meal_type"] == "dinner"
      assert attrs["original_description"] == "2 eggs and toast"
    end

    test "creates attrs with empty map" do
      attrs = MealHelpers.create_meal_attrs(%{})

      assert attrs["meal_type"] == "breakfast"
      assert attrs["original_description"] == "2 eggs and toast"
    end
  end

  describe "assert_meal_structure/1" do
    test "asserts valid meal structure" do
      {:ok, meal} = MealHelpers.create_meal()
      serialized = serialize_meal(meal)

      MealHelpers.assert_meal_structure(serialized)
    end

    test "asserts meal structure with different meal types" do
      for meal_type <- [:breakfast, :lunch, :snack, :dinner] do
        {:ok, meal} = MealHelpers.create_meal(%{meal_type: meal_type})
        serialized = serialize_meal(meal)

        MealHelpers.assert_meal_structure(serialized)
      end
    end

    test "asserts meal structure with different statuses" do
      for status <- [:pending, :processing, :in_review, :confirmed] do
        {:ok, meal} = MealHelpers.create_meal(%{status: status})
        serialized = serialize_meal(meal)

        MealHelpers.assert_meal_structure(serialized)
      end
    end
  end

  describe "assert_meal_response/2" do
    test "asserts meal response with default status 200" do
      {:ok, meal} = MealHelpers.create_meal()

      conn = get(build_conn(), ~p"/journal/meals/#{meal.id}")

      data = MealHelpers.assert_meal_response(conn, 200)
      assert data["id"] == meal.id
    end

    test "asserts meal response with custom status 201" do
      attrs = MealHelpers.create_meal_attrs()

      conn =
        build_conn()
        |> post(~p"/journal/meals", attrs)

      data = MealHelpers.assert_meal_response(conn, 201)
      assert data["meal_type"] == "breakfast"
    end
  end

  describe "assert_meal_data/2" do
    test "asserts meal data without expected attrs" do
      {:ok, meal} = MealHelpers.create_meal()
      serialized = serialize_meal(meal)

      MealHelpers.assert_meal_data(serialized, [])
    end

    test "asserts meal data with meal_type" do
      {:ok, meal} = MealHelpers.create_meal(%{meal_type: :lunch})
      serialized = serialize_meal(meal)

      MealHelpers.assert_meal_data(serialized, meal_type: "lunch")
    end

    test "asserts meal data with status" do
      {:ok, meal} = MealHelpers.create_meal(%{status: :confirmed})
      serialized = serialize_meal(meal)

      MealHelpers.assert_meal_data(serialized, status: "confirmed")
    end

    test "asserts meal data with original_description" do
      {:ok, meal} = MealHelpers.create_meal(%{original_description: "Custom description"})
      serialized = serialize_meal(meal)

      MealHelpers.assert_meal_data(serialized, original_description: "Custom description")
    end

    test "asserts meal data with patient_id" do
      {:ok, meal} = MealHelpers.create_meal(%{patient_id: MealHelpers.poc_patient_id()})
      serialized = serialize_meal(meal)

      MealHelpers.assert_meal_data(serialized, patient_id: MealHelpers.poc_patient_id())
    end

    test "asserts meal data with date" do
      date = ~D[2025-01-27]
      {:ok, meal} = MealHelpers.create_meal(%{date: date})
      serialized = serialize_meal(meal)

      MealHelpers.assert_meal_data(serialized, date: date)
    end

    test "asserts meal data with multiple expected attrs" do
      date = ~D[2025-01-27]
      {:ok, meal} = MealHelpers.create_meal(%{
        meal_type: :dinner,
        status: :in_review,
        original_description: "Full meal",
        date: date
      })
      serialized = serialize_meal(meal)

      MealHelpers.assert_meal_data(serialized, [
        meal_type: "dinner",
        status: "in_review",
        original_description: "Full meal",
        date: date
      ])
    end

    test "asserts meal data with partial expected attrs" do
      {:ok, meal} = MealHelpers.create_meal(%{
        meal_type: :snack,
        status: :pending
      })
      serialized = serialize_meal(meal)

      MealHelpers.assert_meal_data(serialized, [
        meal_type: "snack",
        status: "pending"
      ])
    end

    test "asserts meal data with all expected attrs simultaneously" do
      date = ~D[2025-01-27]
      {:ok, meal} = MealHelpers.create_meal(%{
        meal_type: :lunch,
        status: :confirmed,
        original_description: "Complete test",
        patient_id: MealHelpers.poc_patient_id(),
        date: date
      })
      serialized = serialize_meal(meal)

      MealHelpers.assert_meal_data(serialized, [
        meal_type: "lunch",
        status: "confirmed",
        original_description: "Complete test",
        patient_id: MealHelpers.poc_patient_id(),
        date: date
      ])
    end

    test "asserts meal data without any expected attrs (empty list)" do
      {:ok, meal} = MealHelpers.create_meal()
      serialized = serialize_meal(meal)

      MealHelpers.assert_meal_data(serialized, [])
    end
  end

  describe "constants" do
    test "poc_patient_id returns correct value" do
      assert MealHelpers.poc_patient_id() == 1
    end

    test "other_patient_id returns correct value" do
      assert MealHelpers.other_patient_id() == 999
    end

    test "non_existent_id returns correct value" do
      assert MealHelpers.non_existent_id() == 999_999
    end
  end

  # Helper function to serialize meal for testing
  defp serialize_meal(meal) do
    %{
      "id" => meal.id,
      "patient_id" => meal.patient_id,
      "meal_type" => to_string(meal.meal_type),
      "original_description" => meal.original_description,
      "status" => to_string(meal.status),
      "date" => Date.to_iso8601(meal.date),
      "created_at" => DateTime.to_iso8601(meal.inserted_at),
      "updated_at" => DateTime.to_iso8601(meal.updated_at)
    }
  end
end
