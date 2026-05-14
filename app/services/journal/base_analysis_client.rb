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

    Rails.logger.info(JSON.pretty_generate(payload))
  end

  def debug_request_payload(request_payload)
    request_payload.merge(messages: debug_request_messages(request_payload[:messages]))
  end

  def debug_request_messages(messages)
    Array(messages).map do |message|
      content_key = message.key?(:content) ? :content : "content"
      message.merge(content_key => parsed_debug_content(message[content_key]))
    end
  end

  def parsed_debug_content(content)
    return content unless content.is_a?(String)

    parsed_debug_payload(JSON.parse(content))
  rescue JSON::ParserError
    content
  end

  def debug_response_body(response)
    parsed_debug_response_body(response)
  end

  def parsed_debug_response_body(response)
    parsed = response&.parsed_response
    return parsed_debug_payload(parsed) if parsed.present?

    parsed_debug_payload(JSON.parse(response&.body.to_s))
  rescue JSON::ParserError
    response&.body
  end

  def parsed_debug_payload(payload)
    case payload
    when Array
      payload.map { |item| parsed_debug_payload(item) }
    when Hash
      payload.to_h do |key, value|
        parsed_value = key.to_s == "content" ? parsed_debug_content(value) : parsed_debug_payload(value)
        [ key, parsed_value ]
      end
    else
      payload
    end
  end
end
