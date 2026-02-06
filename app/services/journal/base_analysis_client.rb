class Journal::BaseAnalysisClient
  class TransientError < StandardError; end

  private

  def perform_chat_completion(request_payload:)
    case llm_provider
    when "openai"
      perform_openai_chat_completion(request_payload:)
    else
      raise StandardError, "Unsupported LLM provider: #{llm_provider}"
    end
  end

  def llm_provider
    ENV.fetch("LLM_PROVIDER", "openai")
  end

  def perform_openai_chat_completion(request_payload:)
    api_key = openai_api_key
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = nil

    raise StandardError, "OpenAI API key not configured" if api_key.blank?

    response = send_openai_request(api_key: api_key, request_payload: request_payload)

    if response.code >= 500 || response.code == 429
      raise TransientError, "OpenAI temporary failure status=#{response.code}"
    end

    unless response.code == 200
      raise StandardError, "OpenAI request failed status=#{response.code} body=#{response.body}"
    end

    parse_response(response)
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

  def send_openai_request(api_key:, request_payload:)
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
    return if started_at.nil?

    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(2)
    payload = {
      llm: llm_provider,
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
    return parsed_debug_response_body(response) if Rails.env.development?

    "[redacted]"
  end

  def parsed_debug_response_body(response)
    parsed = response&.parsed_response
    return parsed if parsed.present?

    JSON.parse(response&.body.to_s)
  rescue JSON::ParserError
    response&.body
  end
end
