defmodule JournalWeb.MealControllerTest do
  @moduledoc """
  Integration tests for MealController endpoints.

  Tests cover:
  - Meal creation with LLM processing
  - Meal listing with date filtering
  - Meal retrieval by ID
  - Meal confirmation workflow
  - Error handling and validation
  - Patient isolation

  All tests use authenticated connections with JWT token validation.
  """
  use JournalWeb.ConnCase, async: true

  # Tests that use LLM mocks are safe to run in parallel due to the lock mechanism
  # in LLMHelpers. The @moduletag :llm_mock is kept for documentation purposes
  # to identify tests that use LLM mocking infrastructure.

  alias Journal.Meals.MealEntry
  alias Journal.Repo
  alias Journal.TestHelpers.LLMHelpers
  alias JournalWeb.MealHelpers

  require JournalWeb.MealHelpers

  setup %{conn: conn} do
    # Authenticate connection for all tests
    {conn, patient_id} = authenticate_conn(conn)
    {:ok, conn: conn, patient_id: patient_id}
  end

  describe "POST /journal/meals" do
    test "creates and processes meal successfully", %{conn: conn} do
      attrs = MealHelpers.create_meal_attrs()

      LLMHelpers.with_openai_mock(fn ->
        conn = post(conn, ~p"/journal/meals", attrs)

        data = MealHelpers.assert_meal_response(conn, 201)
        assert data["meal_type"] == "breakfast"
        assert data["original_description"] == "2 eggs and toast"
        assert data["status"] == "in_review"
        assert data["protein_g"] != nil
        assert data["carbs_g"] != nil
        assert data["fat_g"] != nil
        assert data["calories_kcal"] != nil
        assert data["weight_g"] != nil
        assert data["ai_comment"] != nil
      end)
    end

    test "creates meal with date parameter", %{conn: conn} do
      date = ~D[2025-01-27]
      attrs = MealHelpers.create_meal_attrs(%{
        "meal_type" => "lunch",
        "original_description" => "Grilled chicken salad",
        "date" => Date.to_iso8601(date)
      })

      LLMHelpers.with_openai_mock(fn ->
        conn = post(conn, ~p"/journal/meals", attrs)

        data = MealHelpers.assert_meal_response(conn, 201)
        assert data["date"] == Date.to_iso8601(date)
      end)
    end

    test "returns 422 for invalid changeset - missing meal_type", %{conn: conn} do
      attrs = %{
        "original_description" => "Some meal"
      }

      conn = post(conn, ~p"/journal/meals", attrs)

      assert %{"errors" => errors} = json_response(conn, 422)
      assert errors["meal_type"] != nil
    end

    test "returns 422 for invalid changeset - missing original_description", %{conn: conn} do
      attrs = %{
        "meal_type" => "breakfast"
      }

      conn = post(conn, ~p"/journal/meals", attrs)

      assert %{"errors" => errors} = json_response(conn, 422)
      assert errors["original_description"] != nil
    end

    test "returns 422 for invalid changeset - empty original_description", %{conn: conn} do
      attrs = %{
        "meal_type" => "breakfast",
        "original_description" => ""
      }

      conn = post(conn, ~p"/journal/meals", attrs)

      assert %{"errors" => errors} = json_response(conn, 422)
      assert errors["original_description"] != nil
    end

    test "returns 422 for invalid meal_type", %{conn: conn} do
      attrs = %{
        "meal_type" => "invalid_type",
        "original_description" => "Some meal"
      }

      conn = post(conn, ~p"/journal/meals", attrs)

      assert %{"errors" => _errors} = json_response(conn, 422)
    end
  end

  describe "GET /journal/meals" do
    setup %{patient_id: patient_id} do
      date = ~D[2025-01-27]

      # Create meals for the test date
      {:ok, meal1} = MealHelpers.create_meal(%{
        patient_id: patient_id,
        date: date,
        meal_type: :breakfast,
        original_description: "Breakfast meal",
        status: :confirmed
      })

      {:ok, meal2} = MealHelpers.create_meal(%{
        patient_id: patient_id,
        date: date,
        meal_type: :lunch,
        original_description: "Lunch meal",
        status: :in_review
      })

      # Create meal for different date
      {:ok, _meal3} = MealHelpers.create_meal(%{
        patient_id: patient_id,
        date: ~D[2025-01-28],
        meal_type: :dinner,
        original_description: "Dinner meal",
        status: :pending
      })

      %{date: date, meal1: meal1, meal2: meal2}
    end

    test "lists meals for date successfully", %{conn: conn, patient_id: patient_id, date: date, meal1: meal1, meal2: meal2} do
      conn = get(conn, ~p"/journal/meals?date=#{Date.to_iso8601(date)}")

      assert %{"data" => data, "meta" => meta} = json_response(conn, 200)
      assert length(data) == 2
      assert meta["patient_id"] == patient_id
      assert meta["date"] == Date.to_iso8601(date)
      assert meta["count"] == 2

      # Verify meals are in response
      meal_ids = Enum.map(data, & &1["id"])
      assert meal1.id in meal_ids
      assert meal2.id in meal_ids

      # Verify meal structure
      meal = Enum.at(data, 0)
      MealHelpers.assert_meal_structure(meal, patient_id: patient_id)
      assert meal["date"] == Date.to_iso8601(date)
      assert meal["meal_type"] in ["breakfast", "lunch"]
    end

    test "returns empty list when no meals for date", %{conn: conn} do
      date = ~D[2025-12-31]
      conn = get(conn, ~p"/journal/meals?date=#{Date.to_iso8601(date)}")

      assert %{"data" => data, "meta" => meta} = json_response(conn, 200)
      assert data == []
      assert meta["count"] == 0
      assert meta["date"] == Date.to_iso8601(date)
    end

    test "returns 400 for missing date parameter", %{conn: conn} do
      conn = get(conn, ~p"/journal/meals")

      assert %{"error" => error} = json_response(conn, 400)
      assert error == "Missing required parameter: date"
    end

    test "returns 400 for invalid date format", %{conn: conn} do
      conn = get(conn, ~p"/journal/meals?date=invalid-date")

      assert %{"error" => error} = json_response(conn, 400)
      assert error == "Invalid date format. Expected ISO8601 format (YYYY-MM-DD)"
    end

    test "returns 400 for malformed date", %{conn: conn} do
      conn = get(conn, ~p"/journal/meals?date=2025-13-45")

      assert %{"error" => error} = json_response(conn, 400)
      assert error == "Invalid date format. Expected ISO8601 format (YYYY-MM-DD)"
    end

    test "does not return meals from other patients", %{conn: conn, patient_id: patient_id} do
      # Create meal for different patient
      {:ok, _other_meal} = MealHelpers.create_meal(%{
        patient_id: MealHelpers.other_patient_id(),
        date: ~D[2025-01-27],
        meal_type: :breakfast,
        original_description: "Other patient meal",
        status: :confirmed
      })

      conn = get(conn, ~p"/journal/meals?date=2025-01-27")

      assert %{"data" => data} = json_response(conn, 200)
      # Should only return meals for authenticated patient, not other patient
      assert Enum.all?(data, fn meal -> meal["patient_id"] == patient_id end)
    end
  end

  describe "GET /journal/meals/:id" do
    setup %{patient_id: patient_id} do
      {:ok, meal} = MealHelpers.create_meal(%{
        patient_id: patient_id,
        meal_type: :breakfast,
        original_description: "Test meal",
        status: :in_review,
        protein_g: Decimal.new("25.5"),
        carbs_g: Decimal.new("30.0"),
        fat_g: Decimal.new("10.5"),
        calories_kcal: 300,
        weight_g: 250,
        ai_comment: "Test comment"
      })

      %{meal: meal}
    end

    test "returns meal when found", %{conn: conn, meal: meal} do
      conn = get(conn, ~p"/journal/meals/#{meal.id}")

      data = MealHelpers.assert_meal_response(conn, 200)
      assert data["id"] == meal.id
      assert data["patient_id"] == meal.patient_id
      assert data["meal_type"] == "breakfast"
      assert data["original_description"] == "Test meal"
      assert data["status"] == "in_review"
      assert data["protein_g"] == 25.5
      assert data["carbs_g"] == 30.0
      assert data["fat_g"] == 10.5
      assert data["calories_kcal"] == 300
      assert data["weight_g"] == 250
      assert data["ai_comment"] == "Test comment"
    end

    test "returns 404 when meal not found", %{conn: conn} do
      conn = get(conn, ~p"/journal/meals/#{MealHelpers.non_existent_id()}")

      assert %{"error" => error} = json_response(conn, 404)
      assert error == "Resource not found"
    end

    test "handles non-numeric ID gracefully", %{conn: conn} do
      # Note: Currently Ecto raises CastError for non-numeric IDs
      # This test documents current behavior. In the future, we should
      # add ID validation in the controller to return 400 Bad Request
      assert_raise Ecto.Query.CastError, fn ->
        get(conn, ~p"/journal/meals/not-a-number")
      end
    end

    test "returns 404 when meal belongs to different patient", %{conn: conn} do
      # Create meal for different patient
      {:ok, other_meal} = MealHelpers.create_meal(%{
        patient_id: MealHelpers.other_patient_id(),
        meal_type: :breakfast,
        original_description: "Other patient meal",
        status: :pending
      })

      conn = get(conn, ~p"/journal/meals/#{other_meal.id}")

      assert %{"error" => error} = json_response(conn, 404)
      assert error == "Resource not found"
    end

    test "serializes meal with nil nutritional values", %{conn: conn, patient_id: patient_id} do
      {:ok, meal} = MealHelpers.create_meal(%{
        patient_id: patient_id,
        status: :pending,
        protein_g: nil,
        carbs_g: nil,
        fat_g: nil,
        calories_kcal: nil,
        weight_g: nil
      })

      conn = get(conn, ~p"/journal/meals/#{meal.id}")

      data = MealHelpers.assert_meal_response(conn, 200)
      assert data["protein_g"] == nil
      assert data["carbs_g"] == nil
      assert data["fat_g"] == nil
      assert data["calories_kcal"] == nil
      assert data["weight_g"] == nil
    end
  end

  describe "POST /journal/meals/:id/confirm" do
    setup %{patient_id: patient_id} do
      {:ok, meal_in_review} = MealHelpers.create_meal(%{
        patient_id: patient_id,
        meal_type: :breakfast,
        original_description: "Meal in review",
        status: :in_review
      })

      {:ok, meal_pending} = MealHelpers.create_meal(%{
        patient_id: patient_id,
        meal_type: :lunch,
        original_description: "Pending meal",
        status: :pending
      })

      %{meal_in_review: meal_in_review, meal_pending: meal_pending}
    end

    test "confirms meal successfully", %{conn: conn, meal_in_review: meal} do
      conn = post(conn, ~p"/journal/meals/#{meal.id}/confirm")

      data = MealHelpers.assert_meal_response(conn, 200)
      assert data["id"] == meal.id
      assert data["status"] == "confirmed"

      # Verify in database
      updated_meal = Repo.get(MealEntry, meal.id)
      assert updated_meal.status == :confirmed
    end

    test "returns 404 when meal not found", %{conn: conn} do
      conn = post(conn, ~p"/journal/meals/#{MealHelpers.non_existent_id()}/confirm")

      assert %{"error" => error} = json_response(conn, 404)
      assert error == "Resource not found"
    end

    test "handles non-numeric ID gracefully", %{conn: conn} do
      # Note: Currently Ecto raises CastError for non-numeric IDs
      # This test documents current behavior. In the future, we should
      # add ID validation in the controller to return 400 Bad Request
      assert_raise Ecto.Query.CastError, fn ->
        post(conn, ~p"/journal/meals/not-a-number/confirm")
      end
    end

    test "returns 404 when meal belongs to different patient", %{conn: conn} do
      # Create meal for different patient
      {:ok, other_meal} = MealHelpers.create_meal(%{
        patient_id: MealHelpers.other_patient_id(),
        meal_type: :breakfast,
        original_description: "Other patient meal",
        status: :in_review
      })

      conn = post(conn, ~p"/journal/meals/#{other_meal.id}/confirm")

      assert %{"error" => error} = json_response(conn, 404)
      assert error == "Resource not found"
    end

    test "returns 422 for invalid status - meal not in_review", %{conn: conn, meal_pending: meal} do
      conn = post(conn, ~p"/journal/meals/#{meal.id}/confirm")

      assert %{"error" => error} = json_response(conn, 422)
      assert error =~ "Cannot process with status: pending"
      assert error =~ "Expected: in_review"
    end

    test "returns 422 for already confirmed meal", %{conn: conn, patient_id: patient_id} do
      {:ok, confirmed_meal} = MealHelpers.create_meal(%{
        patient_id: patient_id,
        meal_type: :dinner,
        original_description: "Already confirmed",
        status: :confirmed
      })

      conn = post(conn, ~p"/journal/meals/#{confirmed_meal.id}/confirm")

      assert %{"error" => error} = json_response(conn, 422)
      assert error =~ "Cannot process with status: confirmed"
      assert error =~ "Expected: in_review"
    end
  end
end
