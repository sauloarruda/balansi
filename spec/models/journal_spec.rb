require "rails_helper"

RSpec.describe Journal, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:patient) { create(:patient, user:, bmr: 1700) }
  let(:journal) { create(:journal, patient:, date: Date.new(2026, 2, 5)) }

  describe "validations" do
    it "validates score range" do
      journal.score = 6
      expect(journal).not_to be_valid
    end

    it "enforces unique date per patient" do
      create(:journal, patient:, date: Date.new(2026, 2, 5))
      duplicated = build(:journal, patient:, date: Date.new(2026, 2, 5))
      expect(duplicated).not_to be_valid
    end
  end

  describe "business calculations" do
    before do
      Meal.create!(journal:, meal_type: "breakfast", description: "A", calories: 300, status: "confirmed")
      Meal.create!(journal:, meal_type: "lunch", description: "B", calories: 200, status: "pending_patient")
      Exercise.create!(journal:, description: "Run", calories: 250, status: "confirmed")
      Exercise.create!(journal:, description: "Walk", calories: 100, status: "pending_llm")
    end

    it "counts pending and confirmed entries correctly" do
      expect(journal.pending_entries_count).to eq(2)
      expect(journal.confirmed_meals_count).to eq(1)
      expect(journal.confirmed_exercises_count).to eq(1)
    end

    it "calculates effective calories and balance from confirmed entries" do
      expect(journal.effective_calories_consumed).to eq(300)
      expect(journal.exercise_calories_burned).to eq(250)
      expect(journal.effective_calories_burned).to eq(1950)
      expect(journal.effective_balance).to eq(-1650)
      expect(journal.balance_status).to eq("negative")
    end
  end

  describe "#editable?" do
    it "is editable up to two days after the journal date when closed" do
      journal.update!(closed_at: Time.current)

      travel_to(Time.zone.local(2026, 2, 7, 12, 0, 0)) do
        expect(journal.editable?).to be(true)
      end

      travel_to(Time.zone.local(2026, 2, 8, 12, 0, 0)) do
        expect(journal.editable?).to be(false)
      end
    end
  end
end
