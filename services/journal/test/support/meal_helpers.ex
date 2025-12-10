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
    alias Journal.Auth.User
    alias Journal.Auth.Patient

    # Check if patient exists
    case Repo.get(Patient, patient_id) do
      nil ->
        # Patient doesn't exist, create it along with required user
        # Use patient_id as user_id for simplicity in tests
        user_id = patient_id

        # Ensure user exists (check first to avoid constraint errors)
        user = case Repo.get(User, user_id) do
          nil ->
            # Create user using insert_all to set explicit ID
            now = DateTime.utc_now() |> DateTime.truncate(:second)
            Repo.insert_all(User, [%{
              id: user_id,
              name: "Test User #{user_id}",
              email: "test#{user_id}@example.com",
              cognito_id: "cognito-#{user_id}",
              inserted_at: now,
              updated_at: now
            }])
            Repo.get!(User, user_id)
          existing_user ->
            existing_user
        end

        # Create patient using insert_all to set explicit ID
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        Repo.insert_all(Patient, [%{
          id: patient_id,
          user_id: user.id,
          professional_id: 1,
          inserted_at: now,
          updated_at: now
        }])

      _existing_patient ->
        # Patient already exists, nothing to do
        :ok
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
    # Always ensure patient exists - the function checks if it already exists
    if is_integer(patient_id) do
      ensure_patient_exists(patient_id)
    end

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

  defmacro assert_meal_structure(data, opts \\ []) do
    quote do
      assert unquote(data)["id"] != nil

      # Check patient_id if provided, otherwise just verify it exists
      if patient_id = Keyword.get(unquote(opts), :patient_id) do
        assert unquote(data)["patient_id"] == patient_id
      else
        assert unquote(data)["patient_id"] != nil
      end

      assert unquote(data)["meal_type"] in ["breakfast", "lunch", "snack", "dinner"]
      assert unquote(data)["original_description"] != nil
      assert unquote(data)["status"] in ["pending", "processing", "in_review", "confirmed"]
      assert unquote(data)["created_at"] != nil
      assert unquote(data)["updated_at"] != nil
    end
  end

  defmacro assert_meal_response(conn, expected_status \\ 200, opts \\ []) do
    quote do
      assert %{"data" => data} = json_response(unquote(conn), unquote(expected_status))
      assert data["id"] != nil

      # Check patient_id if provided, otherwise just verify it exists
      if patient_id = Keyword.get(unquote(opts), :patient_id) do
        assert data["patient_id"] == patient_id
      else
        assert data["patient_id"] != nil
      end

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
