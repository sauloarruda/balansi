class Journal::MealAnalysisClient
  class TransientError < StandardError; end

  def analyze(description:, meal_type:, user_language: "pt")
    analyze_with_openai(description:, meal_type:, user_language:)
  end

  private

  def analyze_with_openai(description:, meal_type:, user_language:)
    api_key = openai_api_key
    raise StandardError, "OpenAI API key not configured" if api_key.blank?

    request_payload = build_request_payload(description:, meal_type:, user_language:)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = send_request(api_key: api_key, request_payload: request_payload)

    if response.code >= 500 || response.code == 429
      raise TransientError, "OpenAI temporary failure status=#{response.code}"
    end

    unless response.code == 200
      raise StandardError, "OpenAI request failed status=#{response.code} body=#{response.body}"
    end

    normalize_payload(parse_response(response))
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error, SocketError => e
    raise TransientError, e.message
  rescue JSON::ParserError => e
    raise StandardError, "Invalid OpenAI JSON payload: #{e.message}"
  rescue StandardError
    raise
  ensure
    log_llm_debug(request_payload: request_payload, response: response, started_at: started_at)
  end

  def openai_api_key
    Rails.application.credentials.dig(:openai, :api_key).presence || ENV["OPENAI_API_KEY"]
  end

  def openai_model
    Rails.application.credentials.dig(:openai, :model).presence || ENV.fetch("OPENAI_MODEL", "gpt-4.1-mini")
  end

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

  def send_request(api_key:, request_payload:)
    HTTParty.post(
      "https://api.openai.com/v1/chat/completions",
      headers: {
        "Authorization" => "Bearer #{api_key}",
        "Content-Type" => "application/json"
      },
      body: {
        model: request_payload[:model],
        temperature: request_payload[:temperature],
        messages: request_payload[:messages]
      }.to_json,
      timeout: 20
    )
  end

  def parse_response(response)
    content = response.parsed_response.dig("choices", 0, "message", "content").to_s
    JSON.parse(content)
  end

  def log_llm_debug(request_payload:, response:, started_at:)
    return unless Rails.logger.debug?

    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(2)
    payload = {
      llm: "openai",
      request: debug_request_payload(request_payload),
      response: {
        status: response&.code,
        body: debug_response_body(response)
      },
      elapsed_ms: elapsed_ms
    }

    message = if Rails.env.development?
      JSON.pretty_generate(payload)
    else
      payload.except(:request).merge(request: payload[:request].except(:messages)).to_json
    end

    Rails.logger.debug(message)
  end

  def debug_request_payload(request_payload)
    return request_payload if Rails.env.development?

    request_payload.merge(messages: "[redacted]")
  end

  def debug_response_body(response)
    return response&.body if Rails.env.development?

    "[redacted]"
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
      "Você é um nutricionista. Responda apenas com JSON válido, sem markdown."
    else
      "You are a nutrition assistant. Return only valid JSON, without markdown."
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
