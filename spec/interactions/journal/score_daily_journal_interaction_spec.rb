require "rails_helper"

RSpec.describe Journal::ScoreDailyJournalInteraction, type: :interaction do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, language: "pt") }
  let(:patient) { create(:patient, user: user, bmr: 1800, daily_calorie_goal: 2200, steps_goal: 8000, hydration_goal: 2000) }
  let(:journal) do
    Journal.create!(
      patient: patient,
      date: Date.new(2026, 2, 5),
      closed_at: Time.current,
      calories_consumed: 1900,
      calories_burned: 2050,
      feeling_today: "good",
      sleep_quality: "excellent",
      hydration_quality: "good",
      steps_count: 7500,
      daily_note: "Good day overall"
    )
  end
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(cache_store)
  end

  describe ".run" do
    it "updates journal with score and feedback" do
      client = instance_double(Journal::DailyScoringClient)
      allow(client).to receive(:score).and_return(
        {
          s: 4,
          fp: "Good protein intake and consistent hydration.",
          fi: "Consider adding more vegetables to your meals."
        }
      )
      allow_any_instance_of(described_class).to receive(:llm_client).and_return(client)

      result = described_class.run(
        journal: journal,
        user_id: user.id,
        user_language: user.language
      )

      expect(result).to be_valid
      expect(journal.reload.score).to eq(4)
      expect(journal.feedback_positive).to eq("Good protein intake and consistent hydration.")
      expect(journal.feedback_improvement).to eq("Consider adding more vegetables to your meals.")
    end

    it "fails with error when response is missing required fields" do
      client = instance_double(Journal::DailyScoringClient)
      allow(client).to receive(:score).and_return({ s: 3 })
      allow_any_instance_of(described_class).to receive(:llm_client).and_return(client)

      result = described_class.run(
        journal: journal,
        user_id: user.id,
        user_language: user.language
      )

      expect(result).not_to be_valid
      expect(result.errors.full_messages.to_sentence).to include("Não foi possível calcular")
    end

    it "fails with error when score is out of range" do
      client = instance_double(Journal::DailyScoringClient)
      allow(client).to receive(:score).and_return({ s: 7, fp: "Good.", fi: "Improve." })
      allow_any_instance_of(described_class).to receive(:llm_client).and_return(client)

      result = described_class.run(
        journal: journal,
        user_id: user.id,
        user_language: user.language
      )

      expect(result).not_to be_valid
    end

    it "retries transient failures up to MAX_RETRIES" do
      client = instance_double(Journal::DailyScoringClient)
      call_count = 0
      allow(client).to receive(:score) do
        call_count += 1
        raise Journal::DailyScoringClient::TransientError, "temporary" if call_count < 3

        { s: 5, fp: "Excellent day!", fi: "Nothing to improve." }
      end
      allow_any_instance_of(described_class).to receive(:llm_client).and_return(client)
      allow_any_instance_of(described_class).to receive(:sleep)

      result = described_class.run(
        journal: journal,
        user_id: user.id,
        user_language: user.language
      )

      expect(result).to be_valid
      expect(journal.reload.score).to eq(5)
      expect(call_count).to eq(3)
    end

    it "fails gracefully after max transient retries" do
      client = instance_double(Journal::DailyScoringClient)
      allow(client).to receive(:score).and_raise(Journal::DailyScoringClient::TransientError, "always fails")
      allow_any_instance_of(described_class).to receive(:llm_client).and_return(client)
      allow_any_instance_of(described_class).to receive(:sleep)

      result = described_class.run(
        journal: journal,
        user_id: user.id,
        user_language: user.language
      )

      expect(result).not_to be_valid
      expect(result.errors.full_messages.to_sentence).to include("Não foi possível calcular")
    end

    it "fails gracefully on standard errors" do
      client = instance_double(Journal::DailyScoringClient)
      allow(client).to receive(:score).and_raise(StandardError, "unexpected error")
      allow_any_instance_of(described_class).to receive(:llm_client).and_return(client)

      result = described_class.run(
        journal: journal,
        user_id: user.id,
        user_language: user.language
      )

      expect(result).not_to be_valid
    end

    it "enforces daily rate limit" do
      # Fill up the daily limit
      daily_key = "journal:llm:user:#{user.id}:day:#{Time.current.strftime('%Y%m%d')}"
      cache_store.write(daily_key, Journal::ScoreDailyJournalInteraction::DAILY_LIMIT, expires_at: Time.current.end_of_day)

      result = described_class.run(
        journal: journal,
        user_id: user.id,
        user_language: user.language
      )

      expect(result).not_to be_valid
      expect(result.errors.full_messages.to_sentence).to include("excedeu")
    end
  end
end
