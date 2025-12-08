defmodule Journal.Services.LLMService do
  @moduledoc """
  Service for LLM-based nutritional estimation using OpenAI GPT.

  Analyzes meal descriptions and returns estimated nutritional values
  including protein, carbs, fat, calories, weight, and a brief comment.
  """

  require Logger

  @openai_url "https://api.openai.com/v1/chat/completions"

  @system_prompt """
  You are a nutritionist AI assistant. Your task is to estimate the nutritional content of meals based on their description.

  For each meal description, provide your best estimate of:
  - protein_g: grams of protein (decimal, e.g., 25.5)
  - carbs_g: grams of carbohydrates (decimal, e.g., 45.0)
  - fat_g: grams of fat (decimal, e.g., 15.5)
  - calories_kcal: total calories (integer, e.g., 450)
  - weight_g: estimated total weight in grams (integer, e.g., 300)
  - comment: a brief comment (1-2 sentences) about the nutritional quality of the meal in the same language as the meal description

  Consider typical portion sizes when the user doesn't specify quantities.
  Be conservative in your estimates - it's better to slightly underestimate than overestimate.

  IMPORTANT: Respond ONLY with valid JSON in this exact format, no additional text:
  {"protein_g": 25.5, "carbs_g": 45.0, "fat_g": 15.5, "calories_kcal": 450, "weight_g": 300, "comment": "Your comment here"}
  """

  @doc """
  Estimates nutritional information for a meal description using OpenAI.

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
        ai_comment: "Balanced breakfast with good protein and healthy fats from eggs and avocado."
      }}
  """
  def estimate_meal(description) do
    config = Application.get_env(:journal, :openai)

    if config && config[:api_key] do
      estimate_with_openai(description, config)
    else
      Logger.warning("OpenAI API key not configured, using stub estimation")
      {:ok, generate_stub_estimation(description)}
    end
  end

  # OpenAI integration

  defp estimate_with_openai(description, config) do
    api_key = config[:api_key]
    model = config[:model] || "gpt-4o-mini"

    Logger.info("Requesting OpenAI estimation for: #{description}")

    request_body = %{
      model: model,
      messages: [
        %{role: "system", content: @system_prompt},
        %{role: "user", content: "Estimate the nutritional content of this meal: #{description}"}
      ],
      temperature: 0.3,
      max_tokens: 200
    }

    case make_openai_request(api_key, request_body) do
      {:ok, response} ->
        parse_openai_response(response, description)

      {:error, reason} ->
        Logger.error("OpenAI API error: #{inspect(reason)}, falling back to stub")
        {:ok, generate_stub_estimation(description)}
    end
  end

  defp make_openai_request(api_key, body) do
    headers = [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]

    case Req.post(@openai_url, json: body, headers: headers, receive_timeout: 30_000) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("OpenAI API returned status #{status}: #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("OpenAI API request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_openai_response(response, description) do
    with %{"choices" => [%{"message" => %{"content" => content}} | _]} <- response,
         {:ok, parsed} <- parse_json_response(content) do
      estimation = %{
        protein_g: to_decimal(parsed["protein_g"]),
        carbs_g: to_decimal(parsed["carbs_g"]),
        fat_g: to_decimal(parsed["fat_g"]),
        calories_kcal: round_or_default(parsed["calories_kcal"], 0),
        weight_g: round_or_default(parsed["weight_g"], 0),
        ai_comment: parsed["comment"] || "AI nutritional estimation."
      }

      Logger.info("OpenAI estimation complete",
        description: description,
        calories: estimation.calories_kcal,
        protein: Decimal.to_float(estimation.protein_g)
      )

      {:ok, estimation}
    else
      error ->
        Logger.error("Failed to parse OpenAI response: #{inspect(error)}")
        {:ok, generate_stub_estimation(description)}
    end
  end

  defp parse_json_response(content) do
    # Try to extract JSON from the response (sometimes wrapped in markdown)
    content = String.trim(content)

    json_content =
      cond do
        String.starts_with?(content, "{") ->
          content

        String.contains?(content, "```json") ->
          content
          |> String.split("```json")
          |> Enum.at(1, "")
          |> String.split("```")
          |> Enum.at(0, "")
          |> String.trim()

        String.contains?(content, "```") ->
          content
          |> String.split("```")
          |> Enum.at(1, "")
          |> String.trim()

        true ->
          content
      end

    Jason.decode(json_content)
  end

  defp to_decimal(nil), do: Decimal.new("0.0")
  defp to_decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value) when is_binary(value), do: Decimal.new(value)

  defp round_or_default(nil, default), do: default
  defp round_or_default(value, _default) when is_integer(value), do: value
  defp round_or_default(value, _default) when is_float(value), do: round(value)
  defp round_or_default(value, default) when is_binary(value) do
    case Float.parse(value) do
      {num, _} -> round(num)
      :error -> default
    end
  end

  # Fallback stub estimation (when OpenAI is unavailable)

  defp generate_stub_estimation(description) do
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
          {20.0, 30.0, 15.0, 340, 250, "Balanced meal (stub estimation - OpenAI unavailable)."}
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
