require "rails_helper"

RSpec.describe Journal::DailyScoringClient, type: :service do
  let(:client) { described_class.new }
  let(:api_key) { "test-api-key" }
  let(:user) { create(:user, language: "pt") }
  let(:patient) { create(:patient, user: user, bmr: 1800, daily_calorie_goal: 2200, steps_goal: 8000, hydration_goal: 2000) }
  let(:journal) do
    Journal.create!(
      patient: patient,
      date: Date.new(2026, 2, 5),
      closed_at: Time.current,
      calories_consumed: 1950,
      calories_burned: 2100,
      feeling_today: "good",
      sleep_quality: "excellent",
      hydration_quality: "good",
      steps_count: 8500,
      daily_note: nil
    )
  end

  before do
    allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_call_original
    allow(ENV).to receive(:[]).with("OPENAI_MODEL").and_call_original
    allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return(api_key)
    allow(Rails.application.credentials).to receive(:dig).with(:openai, :api_key).and_return(api_key)
    allow(Rails.application.credentials).to receive(:dig).with(:openai, :model).and_return("gpt-4.1-mini")
  end

  def stub_openai(status:, body:)
    stub_request(:post, "https://api.openai.com/v1/chat/completions")
      .with(headers: { "Authorization" => "Bearer #{api_key}" })
      .to_return(status: status, body: body, headers: { "Content-Type" => "application/json" })
  end

  it "returns normalized score payload on success" do
    response_body = {
      choices: [
        {
          message: {
            content: {
              s: 4,
              fp: "Good caloric balance and adequate hydration.",
              fi: "Try to add more vegetables to your lunch."
            }.to_json
          }
        }
      ]
    }.to_json

    stub_openai(status: 200, body: response_body)

    result = client.score(journal: journal, patient: patient, user_language: "pt")

    expect(result).to eq({
      s: 4,
      fp: "Good caloric balance and adequate hydration.",
      fi: "Try to add more vegetables to your lunch."
    })
  end

  it "raises TransientError on rate limited response" do
    stub_openai(status: 429, body: { error: "rate_limited" }.to_json)

    expect {
      client.score(journal: journal, patient: patient, user_language: "pt")
    }.to raise_error(Journal::DailyScoringClient::TransientError)
  end

  it "raises TransientError on server error response" do
    stub_openai(status: 500, body: { error: "internal_server_error" }.to_json)

    expect {
      client.score(journal: journal, patient: patient, user_language: "pt")
    }.to raise_error(Journal::DailyScoringClient::TransientError)
  end

  it "raises StandardError on non-200 non-transient response" do
    stub_openai(status: 400, body: { error: "bad_request" }.to_json)

    expect {
      client.score(journal: journal, patient: patient, user_language: "pt")
    }.to raise_error(StandardError, /OpenAI request failed/)
  end

  it "raises StandardError on missing API key" do
    allow(Rails.application.credentials).to receive(:dig).with(:openai, :api_key).and_return(nil)
    allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return(nil)

    expect {
      client.score(journal: journal, patient: patient, user_language: "pt")
    }.to raise_error(StandardError, /API key not configured/)
  end
end
