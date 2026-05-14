require "rails_helper"

RSpec.describe Journal::CreateMealInteraction, type: :interaction do
  let(:user) { create(:user, language: "pt") }
  let(:patient) { create(:patient, user:) }
  let(:journal_date) { Date.new(2026, 2, 13) }
  let(:attributes) do
    ActionController::Parameters.new(
      meal_type: "dinner",
      description: "Jantar com @[Chicken bowl](recipe:#{recipe.id})"
    ).permit!
  end
  let(:recipe) { create(:recipe, patient:, name: "Chicken bowl", calories: 420) }
  let(:analysis_errors) { ActiveModel::Errors.new(Meal.new) }
  let(:analysis_result) { instance_double(ActiveInteraction::Base, valid?: true, errors: analysis_errors) }

  before do
    allow(Journal::AnalyzeMealInteraction).to receive(:run).and_return(analysis_result)
  end

  it "creates the journal, meal, and recipe references atomically" do
    result = described_class.run(patient:, user:, journal_date:, attributes:)

    expect(result).to be_valid
    meal = result.result.meal
    expect(meal).to be_persisted
    expect(meal.journal.date).to eq(journal_date)
    expect(meal.status.to_s).to eq("pending_llm")
    expect(meal.meal_recipe_references.sole.recipe).to eq(recipe)
    expect(Journal::AnalyzeMealInteraction).to have_received(:run).with(
      meal: meal,
      user_id: user.id,
      description: meal.description,
      meal_type: meal.meal_type,
      user_language: user.language
    )
  end

  it "rolls back a newly created journal when the meal is invalid" do
    invalid_attributes = ActionController::Parameters.new(meal_type: "dinner", description: "").permit!

    expect do
      result = described_class.run(patient:, user:, journal_date:, attributes: invalid_attributes)
      expect(result).not_to be_valid
      expect(result.result.meal).not_to be_persisted
    end.not_to change(Journal, :count)
  end

  it "keeps the meal and exposes analysis errors when LLM analysis fails" do
    failed_errors = ActiveModel::Errors.new(Meal.new)
    failed_errors.add(:base, "LLM indisponível")
    failed_result = instance_double(ActiveInteraction::Base, valid?: false, errors: failed_errors)
    allow(Journal::AnalyzeMealInteraction).to receive(:run).and_return(failed_result)

    result = described_class.run(patient:, user:, journal_date:, attributes:)

    expect(result).to be_valid
    expect(result.result.meal).to be_persisted
    expect(result.result.analysis_errors.full_messages).to include("LLM indisponível")
  end
end
