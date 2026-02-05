require "rails_helper"

RSpec.describe Journal::AnalyzeMealInteraction, type: :interaction do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, language: "pt") }
  let(:patient) { create(:patient, user: user) }
  let(:journal) { create(:journal, patient: patient, date: Date.new(2026, 2, 5)) }
  let(:meal) { Meal.create!(journal: journal, meal_type: "lunch", description: "Frango com arroz", status: "pending_llm") }
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(cache_store)
  end

  describe ".run" do
    it "updates meal with analysis and sets pending_patient" do
      client = instance_double(Journal::MealAnalysisClient)
      allow(client).to receive(:analyze).and_return(
        {
          p: 32,
          c: 45,
          f: 14,
          cal: 430,
          gw: 360,
          cmt: "Boa refeição.",
          feel: 1
        }
      )
      allow_any_instance_of(described_class).to receive(:llm_client).and_return(client)

      result = described_class.run(
        meal: meal,
        user_id: user.id,
        description: meal.description,
        meal_type: meal.meal_type,
        user_language: user.language
      )

      expect(result).to be_valid
      expect(meal.reload.status.to_s).to eq("pending_patient")
      expect(meal.calories).to eq(430)
      expect(meal.ai_comment).to eq("Boa refeição.")
      expect(meal.feeling).to eq(1)
    end

    it "fails when response is malformed" do
      client = instance_double(Journal::MealAnalysisClient)
      allow(client).to receive(:analyze).and_return({ p: 10 })
      allow_any_instance_of(described_class).to receive(:llm_client).and_return(client)

      result = described_class.run(
        meal: meal,
        user_id: user.id,
        description: meal.description,
        meal_type: meal.meal_type,
        user_language: user.language
      )

      expect(result).not_to be_valid
      expect(result.errors.full_messages.to_sentence).to include("Não foi possível analisar sua refeição agora")
      expect(meal.reload.status.to_s).to eq("pending_llm")
    end

    it "retries transient failures up to success" do
      client = instance_double(Journal::MealAnalysisClient)
      call_count = 0
      allow(client).to receive(:analyze) do
        call_count += 1
        raise Journal::MealAnalysisClient::TransientError, "temporary" if call_count < 3

        {
          p: 25,
          c: 40,
          f: 10,
          cal: 350,
          gw: 280,
          cmt: "Resposta após retry.",
          feel: 1
        }
      end

      allow_any_instance_of(described_class).to receive(:llm_client).and_return(client)
      allow_any_instance_of(described_class).to receive(:sleep)

      result = described_class.run(
        meal: meal,
        user_id: user.id,
        description: meal.description,
        meal_type: meal.meal_type,
        user_language: user.language
      )

      expect(result).to be_valid
      expect(call_count).to eq(3)
      expect(meal.reload.status.to_s).to eq("pending_patient")
    end

    it "blocks when hourly rate limit is exceeded" do
      travel_to(Time.zone.local(2026, 2, 5, 10, 0, 0)) do
        hourly_key = "journal:meal:llm:user:#{user.id}:hour:2026020510"
        cache_store.write(hourly_key, 10)

        result = described_class.run(
          meal: meal,
          user_id: user.id,
          description: meal.description,
          meal_type: meal.meal_type,
          user_language: user.language
        )

        expect(result).not_to be_valid
        expect(result.errors.full_messages.to_sentence).to include("Você excedeu seu limite de uso de IA")
      end
    end
  end
end
