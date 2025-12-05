defmodule JournalWeb.MealController do
  use JournalWeb, :controller

  # POC: Using constant user_id. In production, extract from Bearer token.
  @poc_user_id 1

  @doc """
  Creates a new meal entry with pending status.

  POST /meals
  Body: { "meal_type": "breakfast", "original_description": "2 eggs and toast" }
  """
  def create(conn, params) do
    user_id = get_user_id(conn)

    # Phase 2: Return 200 OK stub
    # Phase 4-5: Will integrate with MealService and LLMService
    conn
    |> put_status(:created)
    |> json(%{
      data: %{
        id: 1,
        user_id: user_id,
        date: Date.utc_today() |> Date.to_iso8601(),
        meal_type: Map.get(params, "meal_type", "breakfast"),
        original_description: Map.get(params, "original_description", ""),
        status: "pending",
        # Stub values - will come from LLM in Phase 5
        protein_g: nil,
        carbs_g: nil,
        fat_g: nil,
        calories_kcal: nil,
        weight_g: nil,
        comment: nil
      },
      message: "Meal created successfully (stub response)"
    })
  end

  @doc """
  Lists meals for the current user, optionally filtered by date.

  GET /meals?date=YYYY-MM-DD
  """
  def index(conn, params) do
    user_id = get_user_id(conn)
    date = Map.get(params, "date", Date.utc_today() |> Date.to_iso8601())

    # Phase 2: Return empty list stub
    # Phase 4-5: Will query from database
    conn
    |> put_status(:ok)
    |> json(%{
      data: [],
      meta: %{
        user_id: user_id,
        date: date,
        count: 0
      },
      message: "Meals list (stub response)"
    })
  end

  # POC: Returns constant user_id. Replace with Bearer token extraction in production.
  defp get_user_id(_conn), do: @poc_user_id
end
