class Journal::ExerciseAnalysisClient < Journal::BaseAnalysisClient
  def analyze(description:, user_language: "pt")
    request_payload = build_request_payload(description:, user_language:)
    normalize_payload(perform_chat_completion(request_payload: request_payload))
  end

  private

  def build_request_payload(description:, user_language:)
    {
      model: openai_model,
      temperature: 0.2,
      messages: [
        { role: "system", content: system_prompt(user_language) },
        { role: "user", content: user_prompt(description:, user_language:) }
      ]
    }
  end

  def normalize_payload(parsed)
    {
      d: parsed["d"],
      cal: parsed["cal"],
      n: parsed["n"],
      sd: parsed["sd"]
    }
  end

  def system_prompt(user_language)
    if user_language.to_s.start_with?("pt")
      "Você é um assistente de exercícios. Responda apenas com JSON válido, sem markdown."
    else
      "You are an exercise assistant. Return only valid JSON, without markdown."
    end
  end

  def user_prompt(description:, user_language:)
    <<~PROMPT
      Analyze exercise description and return metrics.

      Lang: #{user_language}
      Description: "#{description}"

      Return JSON:
      - d: duration (minutes)
      - cal: calories burned (kcal)
      - n: NEAT (kcal, 0 if not applicable)
      - sd: structured description (#{user_language}, concise)
    PROMPT
  end
end
