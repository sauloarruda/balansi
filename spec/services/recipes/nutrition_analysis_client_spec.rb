require "rails_helper"

RSpec.describe Recipes::NutritionAnalysisClient, type: :service do
  let(:client) { described_class.new }
  let(:api_key) { "test-api-key" }

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

  it "returns normalized payload on success" do
    response_body = {
      choices: [
        {
          message: {
            content: {
              calories: 420,
              proteins: 24.5,
              carbs: 52.25,
              fats: 11.75
            }.to_json
          }
        }
      ]
    }.to_json

    stub_openai(status: 200, body: response_body)

    result = client.analyze(
      name: "Lentil stew",
      ingredients: "Lentils, carrots, onion",
      instructions: "Cook until tender.",
      portion_size_grams: 200,
      user_language: "en"
    )

    expect(result).to eq({ calories: 420, proteins: 24.5, carbs: 52.25, fats: 11.75 })
  end

  it "sends the recipe context in the prompt" do
    captured_prompt = nil
    response_body = {
      choices: [
        {
          message: {
            content: {
              calories: 300,
              proteins: 18,
              carbs: 36,
              fats: 8
            }.to_json
          }
        }
      ]
    }.to_json

    stub_request(:post, "https://api.openai.com/v1/chat/completions")
      .with(headers: { "Authorization" => "Bearer #{api_key}" }) do |request|
        captured_prompt = JSON.parse(request.body).dig("messages", 1, "content")
        true
      end
      .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })

    client.analyze(
      name: "Chicken bowl",
      ingredients: "Chicken breast, rice, beans",
      instructions: "",
      portion_size_grams: 250,
      user_language: "pt",
      recipe_context: [
        {
          recipe_name: "Rice bowl",
          portion_size_grams: 220,
          calories_per_portion: 410,
          proteins_per_portion: 24.5,
          carbs_per_portion: 52.25,
          fats_per_portion: 9.75
        }
      ]
    )

    payload = JSON.parse(captured_prompt)
    recipe = payload["recipes"].sole

    expect(payload.dig("rules", "recipes_exact")).to be(true)
    expect(payload.dig("recipe", "name")).to eq("Chicken bowl")
    expect(recipe).to include("n" => "Rice bowl", "g" => "220")
    expect(recipe["per_portion"]).to include("cal" => "410", "p" => "24.5", "c" => "52.25", "f" => "9.75")
  end

  it "raises TransientError on rate limited response" do
    stub_openai(status: 429, body: { error: "rate_limited" }.to_json)

    expect {
      client.analyze(
        name: "Lentil stew",
        ingredients: "Lentils",
        instructions: "",
        portion_size_grams: 200,
        user_language: "en"
      )
    }.to raise_error(Recipes::NutritionAnalysisClient::TransientError)
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
      client.analyze(
        name: "Lentil stew",
        ingredients: "Lentils",
        instructions: "",
        portion_size_grams: 200,
        user_language: "en"
      )
    }.to raise_error(StandardError, /Invalid OpenAI JSON payload/)
  end
end
