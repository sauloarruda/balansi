require "rails_helper"

RSpec.describe Journal::BaseAnalysisClient, type: :service do
  subject(:client) { described_class.new }

  describe "#debug_request_payload" do
    it "parses JSON message content in request logs" do
      payload = {
        model: "gpt-4.1-mini",
        temperature: 0.1,
        messages: [
          {
            role: "system",
            content: { role: "nutrition_analysis_assistant", rules: [ "Return JSON only" ] }.to_json
          }
        ]
      }

      result = client.send(:debug_request_payload, payload)

      expect(result.dig(:messages, 0, :content)).to eq(
        "role" => "nutrition_analysis_assistant",
        "rules" => [ "Return JSON only" ]
      )
    end

    it "keeps non-JSON message content unchanged in request logs" do
      payload = {
        messages: [
          { "role" => "user", "content" => "Plain prompt" }
        ]
      }

      result = client.send(:debug_request_payload, payload)

      expect(result.dig(:messages, 0, "content")).to eq("Plain prompt")
    end

    it "does not redact messages outside development" do
      payload = {
        messages: [
          { role: "user", content: { task: "analyze" }.to_json }
        ]
      }

      result = client.send(:debug_request_payload, payload)

      expect(result.dig(:messages, 0, :content)).to eq("task" => "analyze")
    end
  end

  describe "#log_llm_debug" do
    it "logs the complete parsed payload at info level" do
      logger = instance_double(ActiveSupport::Logger, info: nil)
      response = instance_double(
        HTTParty::Response,
        code: 200,
        parsed_response: {
          "choices" => [
            {
              "message" => {
                "content" => { p: 10, c: 20, f: 5, cal: 200, gw: 150, cmt: "OK", feel: 1 }.to_json
              }
            }
          ]
        }
      )
      payload = {
        model: "gpt-4.1-mini",
        temperature: 0.1,
        messages: [
          { role: "user", content: { task: "analyze_meal_nutrition" }.to_json }
        ]
      }
      allow(Rails).to receive(:logger).and_return(logger)

      client.send(:log_llm_debug, request_payload: payload, response: response, started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC))

      expect(logger).to have_received(:info) do |message|
        logged_payload = JSON.parse(message)
        expect(logged_payload.dig("request", "messages", 0, "content")).to eq("task" => "analyze_meal_nutrition")
        expect(logged_payload.dig("response", "body", "choices", 0, "message", "content")).to eq(
          "p" => 10,
          "c" => 20,
          "f" => 5,
          "cal" => 200,
          "gw" => 150,
          "cmt" => "OK",
          "feel" => 1
        )
      end
    end
  end
end
