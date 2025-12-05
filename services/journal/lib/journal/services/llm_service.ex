defmodule Journal.Services.LLMService do
  @moduledoc """
  Service for LLM-based nutritional estimation.

  In production, this will integrate with OpenAI GPT-4 to estimate
  nutritional values from meal descriptions.

  For the POC, returns stub data.
  """

  require Logger

  @doc """
  Estimates nutritional information for a meal description.

  ## Parameters
    - description: Free text description of the meal

  ## Returns
    - {:ok, estimation} with nutritional values
    - {:error, reason} on failure

  ## Example
      iex> LLMService.estimate_meal("2 eggs and toast with avocado")
      {:ok, %{
        protein_g: Decimal.new("18.5"),
        carbs_g: Decimal.new("25.0"),
        fat_g: Decimal.new("22.0"),
        calories_kcal: 380,
        weight_g: 250,
        ai_comment: "Balanced breakfast with good protein and healthy fats."
      }}
  """
  def estimate_meal(description) do
    Logger.info("LLM estimation requested for: #{description}")

    # TODO: Integrate with OpenAI GPT-4
    # For POC, return stub data based on meal description analysis
    estimation = generate_stub_estimation(description)

    Logger.info("LLM estimation complete", estimation: estimation)

    {:ok, estimation}
  end

  # Private functions

  defp generate_stub_estimation(description) do
    # Simple heuristics for POC - will be replaced with real LLM
    description_lower = String.downcase(description)

    {protein, carbs, fat, calories, weight, comment} =
      cond do
        String.contains?(description_lower, "egg") ->
          {18.5, 15.0, 12.0, 250, 200, "Good protein source from eggs."}

        String.contains?(description_lower, ["chicken", "frango"]) ->
          {35.0, 10.0, 8.0, 280, 250, "Excellent lean protein choice."}

        String.contains?(description_lower, ["salad", "salada"]) ->
          {5.0, 15.0, 8.0, 150, 300, "Light meal with vegetables."}

        String.contains?(description_lower, ["rice", "arroz"]) ->
          {8.0, 45.0, 5.0, 260, 200, "Carbohydrate-rich meal."}

        String.contains?(description_lower, ["steak", "carne", "beef"]) ->
          {40.0, 5.0, 25.0, 420, 300, "High protein meal with red meat."}

        String.contains?(description_lower, ["pasta", "macarrão"]) ->
          {12.0, 55.0, 8.0, 350, 250, "Carbohydrate-focused meal."}

        String.contains?(description_lower, ["fish", "peixe", "salmon", "salmão"]) ->
          {30.0, 5.0, 15.0, 280, 200, "Great source of protein and omega-3."}

        true ->
          {20.0, 30.0, 15.0, 340, 250, "Balanced meal (AI estimation pending full integration)."}
      end

    %{
      protein_g: Decimal.new("#{protein}"),
      carbs_g: Decimal.new("#{carbs}"),
      fat_g: Decimal.new("#{fat}"),
      calories_kcal: calories,
      weight_g: weight,
      ai_comment: comment
    }
  end
end

