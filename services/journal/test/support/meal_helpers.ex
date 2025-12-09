defmodule JournalWeb.MealHelpers do
  @moduledoc """
  Test helpers for creating meal entries and asserting meal responses in tests.

  Reduces duplication across controller, service, and model tests by providing
  common patterns for meal creation and validation.

  This module can be used in:
  - Controller tests (uses ConnCase)
  - Service tests (uses DataCase)
  - Model tests (uses DataCase)
  """

  alias Journal.Meals.MealEntry
  alias Journal.Repo

  @poc_patient_id 1
  @other_patient_id 999
  @non_existent_id 999_999

  # Ensures a patient exists in the database for testing purposes.
  # Creates the patient (and associated user if needed) if they don't exist.
  # This is necessary because meal_entries now have a foreign key constraint
  # on patient_id.
  defp ensure_patient_exists(patient_id) do
    # Check if patient exists
    result = Journal.Repo.query!("SELECT id FROM patients WHERE id = $1", [patient_id])

    if length(result.rows) == 0 do
      # Patient doesn't exist, create it along with required user
      # Use patient_id as user_id for simplicity in tests
      user_id = patient_id

      # Ensure user exists (check first to avoid constraint errors)
      user_result = Journal.Repo.query!("SELECT id FROM users WHERE id = $1", [user_id])
      if length(user_result.rows) == 0 do
        # Create user - use a sequence to get next ID if we want auto-increment,
        # but since we're specifying ID, we'll insert directly
        Journal.Repo.query!("""
          INSERT INTO users (id, name, email, cognito_id, inserted_at, updated_at)
          VALUES ($1, $2, $3, $4, NOW(), NOW())
        """, [user_id, "Test User #{user_id}", "test#{user_id}@example.com", "cognito-#{user_id}"])
      end

      # Create patient with the specific ID
      Journal.Repo.query!("""
        INSERT INTO patients (id, user_id, professional_id, inserted_at, updated_at)
        VALUES ($1, $2, $3, NOW(), NOW())
      """, [patient_id, user_id, 1])
    end
  end

  @doc """
  Creates a meal entry in the database with default or overridden attributes.

  ## Parameters
    - `attrs` - Map of attributes to override defaults

  ## Defaults
    - `patient_id`: 1 (POC patient)
    - `date`: Today's date
    - `meal_type`: :breakfast
    - `original_description`: "Test meal"
    - `status`: :pending

  ## Examples

      iex> {:ok, meal} = MealHelpers.create_meal(%{status: :confirmed})
      iex> meal.status
      :confirmed

      iex> {:ok, meal} = MealHelpers.create_meal(%{date: ~D[2025-01-27]})
      iex> meal.date
      ~D[2025-01-27]
  """
  def create_meal(attrs \\ %{}) do
    defaults = %{
      patient_id: @poc_patient_id,
      date: Date.utc_today(),
      meal_type: :breakfast,
      original_description: "Test meal",
      status: :pending
    }

    attrs = Map.merge(defaults, attrs)
    patient_id = attrs[:patient_id]

    # Ensure patient exists before creating meal entry
    ensure_patient_exists(patient_id)

    %MealEntry{}
    |> MealEntry.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a map of meal attributes for API requests.

  ## Parameters
    - `overrides` - Map of attributes to override defaults

  ## Defaults
    - `meal_type`: "breakfast"
    - `original_description`: "2 eggs and toast"

  ## Examples

      iex> attrs = MealHelpers.create_meal_attrs(%{"meal_type" => "lunch"})
      iex> attrs["meal_type"]
      "lunch"
  """
  def create_meal_attrs(overrides \\ %{}) do
    Map.merge(%{
      "meal_type" => "breakfast",
      "original_description" => "2 eggs and toast"
    }, overrides)
  end

  # Controller-specific helpers (macros that require ConnCase with ExUnit and Phoenix.ConnTest)

  defmacro assert_meal_structure(data) do
    quote do
      assert unquote(data)["id"] != nil
      assert unquote(data)["patient_id"] == unquote(@poc_patient_id)
      assert unquote(data)["meal_type"] in ["breakfast", "lunch", "snack", "dinner"]
      assert unquote(data)["original_description"] != nil
      assert unquote(data)["status"] in ["pending", "processing", "in_review", "confirmed"]
      assert unquote(data)["created_at"] != nil
      assert unquote(data)["updated_at"] != nil
    end
  end

  defmacro assert_meal_response(conn, expected_status \\ 200) do
    quote do
      assert %{"data" => data} = json_response(unquote(conn), unquote(expected_status))
      assert data["id"] != nil
      assert data["patient_id"] == unquote(@poc_patient_id)
      assert data["meal_type"] in ["breakfast", "lunch", "snack", "dinner"]
      assert data["original_description"] != nil
      assert data["status"] in ["pending", "processing", "in_review", "confirmed"]
      assert data["created_at"] != nil
      assert data["updated_at"] != nil
      data
    end
  end

  defmacro assert_meal_data(data, expected_attrs \\ []) do
    quote do
      assert unquote(data)["id"] != nil
      assert unquote(data)["patient_id"] == unquote(@poc_patient_id)
      assert unquote(data)["meal_type"] in ["breakfast", "lunch", "snack", "dinner"]
      assert unquote(data)["original_description"] != nil
      assert unquote(data)["status"] in ["pending", "processing", "in_review", "confirmed"]
      assert unquote(data)["created_at"] != nil
      assert unquote(data)["updated_at"] != nil

      if meal_type = Keyword.get(unquote(expected_attrs), :meal_type) do
        assert unquote(data)["meal_type"] == meal_type
      end

      if status = Keyword.get(unquote(expected_attrs), :status) do
        assert unquote(data)["status"] == status
      end

      if original_description = Keyword.get(unquote(expected_attrs), :original_description) do
        assert unquote(data)["original_description"] == original_description
      end

      if patient_id = Keyword.get(unquote(expected_attrs), :patient_id) do
        assert unquote(data)["patient_id"] == patient_id
      end

      if date = Keyword.get(unquote(expected_attrs), :date) do
        assert unquote(data)["date"] == Date.to_iso8601(date)
      end
    end
  end

  # Constants for test use

  def poc_patient_id, do: @poc_patient_id
  def other_patient_id, do: @other_patient_id
  def non_existent_id, do: @non_existent_id
end
