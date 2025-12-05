defmodule Journal.Services.MealService do
  @moduledoc """
  Service for managing meal entries.

  Handles the business logic for creating, updating, and querying meals,
  including integration with the LLM service for nutritional estimation.
  """

  alias Journal.Repo
  alias Journal.Meals.MealEntry
  alias Journal.Services.LLMService

  import Ecto.Query

  @doc """
  Creates a new meal entry with pending status.

  The meal starts in `pending` status and will be processed by the LLM service
  to estimate nutritional values.

  ## Parameters
    - patient_id: The ID of the patient (from Bearer token in production)
    - attrs: Map with meal_type, original_description, and optional date

  ## Returns
    - {:ok, %MealEntry{}} on success
    - {:error, %Ecto.Changeset{}} on validation failure
  """
  def create_meal(patient_id, attrs) do
    attrs =
      attrs
      |> normalize_attrs()
      |> Map.put("patient_id", patient_id)
      |> parse_date()

    %MealEntry{}
    |> MealEntry.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Starts LLM processing for a meal entry.

  Transitions: pending → processing
  """
  def start_processing(%MealEntry{status: :pending} = meal) do
    meal
    |> MealEntry.processing_changeset()
    |> Repo.update()
  end

  def start_processing(%MealEntry{status: status}) do
    {:error, "Cannot start processing meal with status: #{status}"}
  end

  @doc """
  Processes a meal with LLM estimation and updates with results.

  This is the main flow for POC - synchronous processing.
  In production, this would be async.

  Transitions: pending → processing → in_review
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
  """
  def complete_processing(%MealEntry{status: :processing} = meal, estimation) do
    meal
    |> MealEntry.review_changeset(estimation)
    |> Repo.update()
  end

  def complete_processing(%MealEntry{status: status}, _estimation) do
    {:error, "Cannot complete processing for meal with status: #{status}"}
  end

  @doc """
  Confirms a meal entry after user review.

  Transitions: in_review → confirmed
  """
  def confirm_meal(%MealEntry{status: :in_review} = meal) do
    meal
    |> MealEntry.confirm_changeset()
    |> Repo.update()
  end

  def confirm_meal(%MealEntry{status: status}) do
    {:error, "Cannot confirm meal with status: #{status}"}
  end

  @doc """
  Applies manual override to nutritional values.

  Tracks which fields were overridden for transparency.
  """
  def override_values(%MealEntry{} = meal, attrs) do
    meal
    |> MealEntry.override_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Lists meals for a patient, optionally filtered by date.
  """
  def list_meals(patient_id, opts \\ []) do
    query =
      MealEntry
      |> where([m], m.patient_id == ^patient_id)
      |> order_by([m], desc: m.date, desc: m.inserted_at)

    query =
      case Keyword.get(opts, :date) do
        nil -> query
        date -> where(query, [m], m.date == ^date)
      end

    query =
      case Keyword.get(opts, :status) do
        nil -> query
        status -> where(query, [m], m.status == ^status)
      end

    Repo.all(query)
  end

  @doc """
  Gets a single meal entry by ID for a patient.
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

  defp parse_date(%{"date" => date} = attrs) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, parsed_date} -> Map.put(attrs, "date", parsed_date)
      {:error, _} -> attrs
    end
  end

  defp parse_date(%{"date" => %Date{}} = attrs), do: attrs

  defp parse_date(attrs) do
    Map.put_new(attrs, "date", Date.utc_today())
  end
end
