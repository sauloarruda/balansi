require "rails_helper"

RSpec.describe Journal::AnalyzeExerciseInteraction, type: :interaction do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, language: "pt") }
  let(:patient) { create(:patient, user: user) }
  let(:journal) { create(:journal, patient: patient, date: Date.new(2026, 2, 5)) }
  let(:exercise) { Exercise.create!(journal: journal, description: "Corrida moderada", status: "pending_llm") }
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(cache_store)
  end

  describe ".run" do
    it "updates exercise with analysis and sets pending_patient" do
      client = instance_double(Journal::ExerciseAnalysisClient)
      allow(client).to receive(:analyze).and_return(
        {
          d: 35,
          cal: 320,
          n: 10,
          sd: "Corrida moderada por 35 minutos"
        }
      )
      allow_any_instance_of(described_class).to receive(:llm_client).and_return(client)

      result = described_class.run(
        exercise: exercise,
        user_id: user.id,
        description: exercise.description,
        user_language: user.language
      )

      expect(result).to be_valid
      expect(exercise.reload.status.to_s).to eq("pending_patient")
      expect(exercise.duration).to eq(35)
      expect(exercise.calories).to eq(320)
      expect(exercise.neat).to eq(10)
      expect(exercise.structured_description).to eq("Corrida moderada por 35 minutos")
    end

    it "fails when response is malformed" do
      client = instance_double(Journal::ExerciseAnalysisClient)
      allow(client).to receive(:analyze).and_return({ d: 20 })
      allow_any_instance_of(described_class).to receive(:llm_client).and_return(client)

      result = described_class.run(
        exercise: exercise,
        user_id: user.id,
        description: exercise.description,
        user_language: user.language
      )

      expect(result).not_to be_valid
      expect(result.errors.full_messages.to_sentence).to include("Não foi possível analisar seu exercício agora")
      expect(exercise.reload.status.to_s).to eq("pending_llm")
    end

    it "retries transient failures up to success" do
      client = instance_double(Journal::ExerciseAnalysisClient)
      call_count = 0
      allow(client).to receive(:analyze) do
        call_count += 1
        raise Journal::ExerciseAnalysisClient::TransientError, "temporary" if call_count < 3

        {
          d: 25,
          cal: 220,
          n: 0,
          sd: "Caminhada rápida por 25 minutos"
        }
      end

      allow_any_instance_of(described_class).to receive(:llm_client).and_return(client)
      allow_any_instance_of(described_class).to receive(:sleep)

      result = described_class.run(
        exercise: exercise,
        user_id: user.id,
        description: exercise.description,
        user_language: user.language
      )

      expect(result).to be_valid
      expect(call_count).to eq(3)
      expect(exercise.reload.status.to_s).to eq("pending_patient")
    end

    it "blocks when hourly rate limit is exceeded" do
      travel_to(Time.zone.local(2026, 2, 5, 10, 0, 0)) do
        hourly_key = "journal:llm:user:#{user.id}:hour:2026020510"
        cache_store.write(hourly_key, 10)

        result = described_class.run(
          exercise: exercise,
          user_id: user.id,
          description: exercise.description,
          user_language: user.language
        )

        expect(result).not_to be_valid
        expect(result.errors.full_messages.to_sentence).to include("Você excedeu seu limite de uso de IA")
      end
    end
  end
end
