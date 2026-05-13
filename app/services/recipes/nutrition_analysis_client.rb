class Recipes::NutritionAnalysisClient < Journal::BaseAnalysisClient
  def analyze(name:, ingredients:, instructions:, portion_size_grams:, user_language: "pt")
    request_payload = build_request_payload(name:, ingredients:, instructions:, portion_size_grams:, user_language:)
    normalize_payload(perform_chat_completion(request_payload: request_payload))
  end

  private

  def build_request_payload(name:, ingredients:, instructions:, portion_size_grams:, user_language:)
    {
      model: openai_model,
      temperature: 0.2,
      messages: [
        { role: "system", content: system_prompt(user_language) },
        { role: "user", content: user_prompt(name:, ingredients:, instructions:, portion_size_grams:, user_language:) }
      ]
    }
  end

  def normalize_payload(parsed)
    {
      calories: parsed["calories"],
      proteins: parsed["proteins"],
      carbs: parsed["carbs"],
      fats: parsed["fats"]
    }
  end

  def system_prompt(user_language)
    if user_language.to_s.start_with?("pt")
      "Você é um nutricionista. Responda apenas com JSON válido, sem markdown. Estime os valores nutricionais de uma porção da receita com realismo."
    else
      "You are a nutrition assistant. Return only valid JSON, without markdown. Realistically estimate nutrition values for one recipe portion."
    end
  end

  def user_prompt(name:, ingredients:, instructions:, portion_size_grams:, user_language:)
    <<~PROMPT
      Analyze this recipe and return nutrition data for one portion.

      Lang: #{user_language}
      Recipe name: "#{name}"
      Portion size: #{portion_size_grams} g
      Ingredients:
      #{ingredients}

      Instructions:
      #{instructions.presence || "-"}

      Return JSON:
      - calories: calories (kcal) for one portion
      - proteins: proteins (g) for one portion
      - carbs: carbs (g) for one portion
      - fats: fats (g) for one portion
    PROMPT
  end
end
