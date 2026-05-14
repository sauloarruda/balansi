require "rails_helper"

RSpec.describe Journal::UpdateMealInteraction, type: :interaction do
  let(:user) { create(:user, language: "pt") }
  let(:patient) { create(:patient, user:) }
  let(:journal) { create(:journal, patient:, date: Date.new(2026, 2, 14)) }
  let(:meal) do
    Meal.create!(
      journal: journal,
      meal_type: "lunch",
      description: "Arroz",
      status: "pending_patient",
      calories: 400,
      proteins: 20,
      carbs: 50,
      fats: 10,
      gram_weight: 300
    )
  end
  let(:analysis_errors) { ActiveModel::Errors.new(Meal.new) }
  let(:analysis_result) { instance_double(ActiveInteraction::Base, valid?: true, errors: analysis_errors) }

  before do
    allow(Journal::AnalyzeMealInteraction).to receive(:run).and_return(analysis_result)
  end

  it "updates and confirms a meal" do
    attributes = ActionController::Parameters.new(calories: 450, proteins: 24, carbs: 52, fats: 12, gram_weight: 330).permit!

    result = described_class.run(meal:, patient:, user:, attributes:, confirm: true)

    expect(result).to be_valid
    expect(meal.reload.status.to_s).to eq("confirmed")
    expect(meal.calories).to eq(450)
    expect(meal.proteins).to eq(24)
  end

  it "reprocesses a meal and refreshes recipe references in one transaction" do
    old_recipe = create(:recipe, patient:, name: "Old rice")
    new_recipe = create(:recipe, patient:, name: "New chicken")
    create(:meal_recipe_reference, meal:, recipe: old_recipe)
    attributes = ActionController::Parameters.new(
      meal_type: "dinner",
      description: "Jantar com @[New chicken](recipe:#{new_recipe.id})"
    ).permit!

    result = described_class.run(meal:, patient:, user:, attributes:, reprocess: true)

    expect(result).to be_valid
    expect(meal.reload.meal_type).to eq("dinner")
    expect(meal.meal_recipe_references.sole.recipe).to eq(new_recipe)
    expect(Journal::AnalyzeMealInteraction).to have_received(:run).with(
      meal: meal,
      user_id: user.id,
      description: meal.description,
      meal_type: meal.meal_type,
      user_language: user.language
    )
  end

  it "rolls back reprocess edits when the meal update is invalid" do
    recipe = create(:recipe, patient:, name: "Original recipe")
    create(:meal_recipe_reference, meal:, recipe:)
    attributes = ActionController::Parameters.new(meal_type: "dinner", description: "").permit!

    result = described_class.run(meal:, patient:, user:, attributes:, reprocess: true)

    expect(result).not_to be_valid
    expect(meal.reload.meal_type).to eq("lunch")
    expect(meal.description).to eq("Arroz")
    expect(meal.meal_recipe_references.sole.recipe).to eq(recipe)
  end

  it "restores the previous status and exposes analysis errors when reprocess analysis fails" do
    failed_errors = ActiveModel::Errors.new(Meal.new)
    failed_errors.add(:base, "LLM indisponível")
    failed_result = instance_double(ActiveInteraction::Base, valid?: false, errors: failed_errors)
    allow(Journal::AnalyzeMealInteraction).to receive(:run).and_return(failed_result)
    attributes = ActionController::Parameters.new(meal_type: "dinner", description: "Frango").permit!

    result = described_class.run(meal:, patient:, user:, attributes:, reprocess: true)

    expect(result).to be_valid
    expect(meal.reload.status.to_s).to eq("pending_patient")
    expect(result.result.analysis_errors.full_messages).to include("LLM indisponível")
  end
end
