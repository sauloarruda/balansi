class Journal::MealAnalysisClient < Journal::BaseAnalysisClient
  def analyze(description:, meal_type:, user_language: "pt")
    request_payload = build_request_payload(description:, meal_type:, user_language:)
    normalize_payload(perform_chat_completion(request_payload: request_payload))
  end

  private

  def build_request_payload(description:, meal_type:, user_language:)
    {
      model: openai_model,
      temperature: 0.2,
      messages: [
        { role: "system", content: system_prompt(user_language) },
        { role: "user", content: user_prompt(description:, meal_type:, user_language:) }
      ]
    }
  end

  def normalize_payload(parsed)
    {
      p: parsed["p"],
      c: parsed["c"],
      f: parsed["f"],
      cal: parsed["cal"],
      gw: parsed["gw"],
      cmt: parsed["cmt"],
      feel: parsed["feel"]
    }
  end

  def system_prompt(user_language)
    if user_language.to_s.start_with?("pt")
      "Você é um nutricionista. Responda apenas com JSON válido, sem markdown. Seja bastante realista ao estimar as calorias e peso."
    else
      "You are a nutrition assistant. Return only valid JSON, without markdown. Be very realistic when estimating calories and weight."
    end
  end

  def user_prompt(description:, meal_type:, user_language:)
    <<~PROMPT
      Analyze meal description and return nutrition data.

      Lang: #{user_language}
      Type: #{meal_type}
      Description: "#{description}"

      Return JSON:
      - p: proteins (g)
      - c: carbs (g)
      - f: fats (g)
      - cal: calories (kcal)
      - gw: weight (g)
      - cmt: brief comment (#{user_language}, 2-3 sentences)
      - feel: 1 if nutritionally good/balanced, 0 if not ideal
    PROMPT
  end
end
