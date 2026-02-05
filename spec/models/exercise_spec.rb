require "rails_helper"

RSpec.describe Exercise, type: :model do
  let(:patient) { create(:patient, user: create(:user)) }
  let(:journal) { create(:journal, patient:, date: Date.new(2026, 2, 10)) }

  it "is valid with minimum required fields" do
    exercise = described_class.new(journal:, description: "Walk 30 min")
    expect(exercise).to be_valid
  end

  it "is pending by default" do
    exercise = described_class.create!(journal:, description: "Walk 30 min")
    expect(exercise.pending?).to be(true)
  end

  it "transitions status through workflow methods" do
    exercise = described_class.create!(journal:, description: "Walk 30 min")
    exercise.mark_as_pending_patient!
    expect(exercise.status.to_s).to eq("pending_patient")
    exercise.confirm!
    expect(exercise.status.to_s).to eq("confirmed")
    exercise.reprocess_with_ai!
    expect(exercise.status.to_s).to eq("pending_llm")
  end
end
