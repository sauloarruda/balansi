require "rails_helper"

RSpec.describe Journal::MealAnalysisClient, type: :service do
  let(:client) { described_class.new }
  let(:api_key) { "test-api-key" }

  before do
    allow(Rails.application.credentials).to receive(:dig).with(:openai, :api_key).and_return(api_key)
    allow(Rails.application.credentials).to receive(:dig).with(:openai, :model).and_return("gpt-4.1-mini")
  end

  def stub_openai(status:, body:)
    stub_request(:post, "https://api.openai.com/v1/chat/completions")
      .with(headers: { "Authorization" => "Bearer #{api_key}" })
      .to_return(status: status, body: body, headers: { "Content-Type" => "application/json" })
  end

  it "returns normalized payload on success" do
    response_body = {
      choices: [
        {
          message: {
            content: {
              p: 10,
              c: 20,
              f: 5,
              cal: 200,
              gw: 150,
              cmt: "OK",
              feel: 1
            }.to_json
          }
        }
      ]
    }.to_json

    stub_openai(status: 200, body: response_body)

    result = client.analyze(description: "Frango", meal_type: "lunch", user_language: "pt")

    expect(result).to eq({ p: 10, c: 20, f: 5, cal: 200, gw: 150, cmt: "OK", feel: 1 })
  end

  it "raises TransientError on rate limited response" do
    stub_openai(status: 429, body: { error: "rate_limited" }.to_json)

    expect {
      client.analyze(description: "Frango", meal_type: "lunch", user_language: "pt")
    }.to raise_error(Journal::MealAnalysisClient::TransientError)
  end

  it "raises StandardError on non-200 response" do
    stub_openai(status: 400, body: { error: "bad_request" }.to_json)

    expect {
      client.analyze(description: "Frango", meal_type: "lunch", user_language: "pt")
    }.to raise_error(StandardError, /OpenAI request failed/)
  end

  it "raises StandardError on invalid JSON content" do
    response_body = {
      choices: [
        {
          message: {
            content: "invalid-json"
          }
        }
      ]
    }.to_json

    stub_openai(status: 200, body: response_body)

    expect {
      client.analyze(description: "Frango", meal_type: "lunch", user_language: "pt")
    }.to raise_error(StandardError, /Invalid OpenAI JSON payload/)
  end
end
