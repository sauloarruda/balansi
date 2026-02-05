require "rails_helper"

RSpec.describe Meal, type: :model do
  let(:patient) { create(:patient, user: create(:user)) }
  let(:journal) { create(:journal, patient:, date: Date.new(2026, 2, 10)) }

  it "is valid with minimum required fields" do
    meal = described_class.new(journal:, meal_type: "breakfast", description: "Eggs")
    expect(meal).to be_valid
  end

  it "is pending by default" do
    meal = described_class.create!(journal:, meal_type: "breakfast", description: "Eggs")
    expect(meal.pending?).to be(true)
  end

  it "transitions status through workflow methods" do
    meal = described_class.create!(journal:, meal_type: "breakfast", description: "Eggs")
    meal.mark_as_pending_patient!
    expect(meal.status.to_s).to eq("pending_patient")
    meal.confirm!
    expect(meal.status.to_s).to eq("confirmed")
    meal.reprocess_with_ai!
    expect(meal.status.to_s).to eq("pending_llm")
  end
end
