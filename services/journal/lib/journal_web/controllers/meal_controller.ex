defmodule JournalWeb.MealController do
  use JournalWeb, :controller

  alias Journal.Services.MealService

  # POC: Using constant patient_id. In production, extract from Bearer token.
  @poc_patient_id 1

  @doc """
  Creates a new meal entry and processes with LLM.

  POST /meals
  Body: { "meal_type": "breakfast", "original_description": "2 eggs and toast" }

  Flow:
  1. Creates meal with status: pending
  2. Processes with LLM (sync for POC)
  3. Returns meal with status: in_review and estimated values
  """
  def create(conn, params) do
    patient_id = get_patient_id(conn)

    with {:ok, meal} <- MealService.create_meal(patient_id, params),
         {:ok, processed_meal} <- MealService.process_with_llm(meal) do
      conn
      |> put_status(:created)
      |> json(%{data: serialize_meal(processed_meal)})
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})

      {:error, reason} when is_binary(reason) ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: reason})
    end
  end

  @doc """
  Lists meals for the current patient, optionally filtered by date.

  GET /meals
  GET /meals?date=2025-12-05
  GET /meals?status=confirmed
  """
  def index(conn, params) do
    patient_id = get_patient_id(conn)

    opts =
      []
      |> maybe_add_date_filter(params)
      |> maybe_add_status_filter(params)

    meals = MealService.list_meals(patient_id, opts)

    conn
    |> put_status(:ok)
    |> json(%{
      data: Enum.map(meals, &serialize_meal/1),
      meta: %{
        patient_id: patient_id,
        count: length(meals)
      }
    })
  end

  @doc """
  Gets a specific meal by ID.

  GET /meals/:id
  """
  def show(conn, %{"id" => id}) do
    patient_id = get_patient_id(conn)

    case MealService.get_meal(patient_id, id) do
      {:ok, meal} ->
        conn
        |> put_status(:ok)
        |> json(%{data: serialize_meal(meal)})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Meal not found"})
    end
  end

  @doc """
  Confirms a meal after user review.

  POST /meals/:id/confirm
  """
  def confirm(conn, %{"id" => id}) do
    patient_id = get_patient_id(conn)

    with {:ok, meal} <- MealService.get_meal(patient_id, id),
         {:ok, confirmed_meal} <- MealService.confirm_meal(meal) do
      conn
      |> put_status(:ok)
      |> json(%{data: serialize_meal(confirmed_meal)})
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Meal not found"})

      {:error, reason} when is_binary(reason) ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: reason})
    end
  end

  # Private functions

  defp get_patient_id(_conn), do: @poc_patient_id

  defp serialize_meal(meal) do
    %{
      id: meal.id,
      patient_id: meal.patient_id,
      date: Date.to_iso8601(meal.date),
      meal_type: meal.meal_type,
      original_description: meal.original_description,
      protein_g: decimal_to_float(meal.protein_g),
      carbs_g: decimal_to_float(meal.carbs_g),
      fat_g: decimal_to_float(meal.fat_g),
      calories_kcal: meal.calories_kcal,
      weight_g: meal.weight_g,
      ai_comment: meal.ai_comment,
      status: meal.status,
      has_manual_override: meal.has_manual_override,
      created_at: DateTime.to_iso8601(meal.inserted_at),
      updated_at: DateTime.to_iso8601(meal.updated_at)
    }
  end

  defp decimal_to_float(nil), do: nil
  defp decimal_to_float(%Decimal{} = d), do: Decimal.to_float(d)

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp maybe_add_date_filter(opts, %{"date" => date_string}) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> Keyword.put(opts, :date, date)
      _ -> opts
    end
  end

  defp maybe_add_date_filter(opts, _), do: opts

  defp maybe_add_status_filter(opts, %{"status" => status}) do
    Keyword.put(opts, :status, String.to_existing_atom(status))
  rescue
    ArgumentError -> opts
  end

  defp maybe_add_status_filter(opts, _), do: opts
end
