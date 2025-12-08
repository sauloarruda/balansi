defmodule Journal.Services.MealService do
  @moduledoc """
  Service for managing meal entries.

  Handles the business logic for creating, updating, and querying meals,
  including integration with the LLM service for nutritional estimation.
  """

  alias Journal.Repo
  alias Journal.Meals.MealEntry
  alias Journal.Services.LLMService
  alias Journal.Helpers.DateHelper

  import Ecto.Query

  @doc """
  Creates a new meal entry with pending status.

  The meal starts in `pending` status and will be processed by the LLM service
  to estimate nutritional values.

  ## Parameters
    - patient_id: The ID of the patient (from Bearer token in production)
    - attrs: Map with meal_type, original_description, and optional date
      - `meal_type`: Atom (`:breakfast`, `:lunch`, `:snack`, `:dinner`)
      - `original_description`: String description of the meal (1-1024 chars)
      - `date`: Optional Date struct or ISO8601 string (defaults to today)

  ## Returns
    - {:ok, %MealEntry{}} on success
    - {:error, %Ecto.Changeset{}} on validation failure

  ## Examples

      iex> attrs = %{meal_type: :breakfast, original_description: "2 eggs and toast"}
      iex> {:ok, meal} = MealService.create_meal(1, attrs)
      iex> meal.status
      :pending
      iex> meal.date
      ~D[2025-01-27]

      iex> attrs = %{meal_type: :lunch, original_description: "Salad", date: "2024-01-15"}
      iex> {:ok, meal} = MealService.create_meal(1, attrs)
      iex> meal.date
      ~D[2024-01-15]
  """
  def create_meal(patient_id, attrs) do
    attrs =
      attrs
      |> normalize_attrs()
      |> Map.put("patient_id", patient_id)
      |> DateHelper.normalize_date_from_attrs()

    %MealEntry{}
    |> MealEntry.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Starts LLM processing for a meal entry.

  Transitions: pending → processing

  ## Returns
    - {:ok, %MealEntry{}} on success
    - {:error, {:invalid_status, status, expected: :pending}} when meal is not in pending status
    - {:error, %Ecto.Changeset{}} on database update failure
  """
  def start_processing(%MealEntry{status: :pending} = meal) do
    meal
    |> MealEntry.processing_changeset()
    |> Repo.update()
  end

  def start_processing(%MealEntry{status: status}) do
    {:error, {:invalid_status, status, expected: :pending}}
  end

  @doc """
  Processes a meal with LLM estimation and updates with results.

  This is the main flow for POC - synchronous processing.
  In production, this would be async.

  Transitions: pending → processing → in_review

  TODO: When implementing async worker, add proper error handling to prevent
  meals from getting stuck in `:processing` status if LLM call fails.
  Consider adding retry logic, timeouts, and status rollback on failure.

  ## Parameters
    - meal: The meal entry to process (must be in `:pending` status)

  ## Returns
    - {:ok, %MealEntry{}} on success (meal will be in `:in_review` status)
    - {:error, {:invalid_status, status, expected: :pending}} when meal is not in pending status
    - {:error, reason} when LLM service fails (reason depends on LLMService implementation)
    - {:error, %Ecto.Changeset{}} on validation or database update failure

  ## Examples

      iex> meal = %MealEntry{status: :pending, original_description: "2 eggs"}
      iex> {:ok, processed} = MealService.process_with_llm(meal)
      iex> processed.status
      :in_review
      iex> processed.protein_g
      #Decimal<...>
  """
  def process_with_llm(%MealEntry{} = meal) do
    with {:ok, processing_meal} <- start_processing(meal),
         {:ok, estimation} <- LLMService.estimate_meal(meal.original_description),
         {:ok, reviewed_meal} <- complete_processing(processing_meal, estimation) do
      {:ok, reviewed_meal}
    end
  end

  @doc """
  Completes LLM processing with estimation results.

  Transitions: processing → in_review

  ## Parameters
    - meal: The meal entry in processing status
    - estimation: Map with nutritional values from LLM service

  ## Returns
    - {:ok, %MealEntry{}} on success
    - {:error, {:invalid_status, status, expected: :processing}} when meal is not in processing status
    - {:error, %Ecto.Changeset{}} on validation or database update failure

  ## Examples

      iex> meal = %MealEntry{status: :processing, id: 1}
      iex> estimation = %{protein_g: Decimal.new("25.0"), carbs_g: Decimal.new("30.0")}
      iex> MealService.complete_processing(meal, estimation)
      {:ok, %MealEntry{status: :in_review, ...}}
  """
  def complete_processing(%MealEntry{status: :processing} = meal, estimation) do
    meal
    |> MealEntry.review_changeset(estimation)
    |> Repo.update()
  end

  def complete_processing(%MealEntry{status: status}, _estimation) do
    {:error, {:invalid_status, status, expected: :processing}}
  end

  @doc """
  Confirms a meal entry after user review.

  Transitions: in_review → confirmed

  ## Returns
    - {:ok, %MealEntry{}} on success
    - {:error, {:invalid_status, status, expected: :in_review}} when meal is not in in_review status
    - {:error, %Ecto.Changeset{}} on database update failure

  ## Examples

      iex> meal = %MealEntry{status: :in_review, id: 1}
      iex> MealService.confirm_meal(meal)
      {:ok, %MealEntry{status: :confirmed, ...}}
  """
  def confirm_meal(%MealEntry{status: :in_review} = meal) do
    meal
    |> MealEntry.confirm_changeset()
    |> Repo.update()
  end

  def confirm_meal(%MealEntry{status: status}) do
    {:error, {:invalid_status, status, expected: :in_review}}
  end

  @doc """
  Applies manual override to nutritional values.

  Tracks which fields were overridden for transparency.

  ## Parameters
    - meal: The meal entry to override
    - attrs: Map with nutritional values to override (keys can be atoms or strings)
      Valid keys: `:protein_g`, `:carbs_g`, `:fat_g`, `:calories_kcal`, `:weight_g`

  ## Returns
    - {:ok, %MealEntry{}} on success
    - {:error, %Ecto.Changeset{}} on validation failure

  ## Examples

      iex> meal = %MealEntry{protein_g: Decimal.new("20.0")}
      iex> attrs = %{"protein_g" => Decimal.new("25.0")}
      iex> {:ok, updated} = MealService.override_values(meal, attrs)
      iex> updated.protein_g
      #Decimal<25.0>
      iex> updated.has_manual_override
      true
  """
  def override_values(%MealEntry{} = meal, attrs) do
    meal
    |> MealEntry.override_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Lists meals for a patient filtered by date.

  Note: Pagination is not implemented as the expected volume of meal entries
  per patient per day is low. If volume increases significantly, pagination
  should be reconsidered.

  ## Parameters
    - patient_id: The ID of the patient
    - date: The date to filter meals by (Date struct)

  ## Returns
    - List of `%MealEntry{}` structs for the specified date, ordered by inserted_at (desc)

  ## Examples

      iex> MealService.list_meals(1, ~D[2024-01-15])
      [%MealEntry{date: ~D[2024-01-15]}, ...]
  """
  def list_meals(patient_id, date) do
    MealEntry
    |> where([m], m.patient_id == ^patient_id and m.date == ^date)
    |> order_by([m], desc: m.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single meal entry by ID for a patient.

  ## Parameters
    - patient_id: The ID of the patient
    - meal_id: The ID of the meal entry

  ## Returns
    - {:ok, %MealEntry{}} when meal is found and belongs to the patient
    - {:error, :not_found} when meal is not found or doesn't belong to the patient

  ## Examples

      iex> MealService.get_meal(1, 123)
      {:ok, %MealEntry{id: 123, patient_id: 1, ...}}

      iex> MealService.get_meal(1, 999)
      {:error, :not_found}
  """
  def get_meal(patient_id, meal_id) do
    MealEntry
    |> where([m], m.id == ^meal_id and m.patient_id == ^patient_id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      meal -> {:ok, meal}
    end
  end

  # Private functions

  defp normalize_attrs(attrs) when is_map(attrs) do
    # Convert atom keys to string keys for consistency
    Enum.reduce(attrs, %{}, fn
      {key, value}, acc when is_atom(key) -> Map.put(acc, to_string(key), value)
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp normalize_attrs(attrs) do
    require Logger
    Logger.warning("normalize_attrs received non-map input: #{inspect(attrs)}")
    %{}
  end
end
