require "rails_helper"

RSpec.describe Journal::ResolveRecipeReferencesInteraction, type: :interaction do
  let(:patient) { create(:patient, user: create(:user)) }
  let(:other_patient) { create(:patient, user: create(:user)) }
  let(:journal) { create(:journal, patient:, date: Date.new(2026, 2, 12)) }
  let(:meal) { Meal.create!(journal:, meal_type: "lunch", description:) }
  let(:recipe) { create(:recipe, patient:, name: "Chicken bowl", portion_size_grams: 250, calories: 450, proteins: 34.5, carbs: 48.25, fats: 11.75) }
  let(:description) { "Almoço com @[Chicken bowl](recipe:#{recipe.id})" }

  it "creates a snapshot for a valid recipe mention" do
    result = described_class.run(meal:, patient:, description:)

    expect(result).to be_valid
    reference = meal.meal_recipe_references.sole
    expect(reference.recipe).to eq(recipe)
    expect(reference.recipe_name).to eq("Chicken bowl")
    expect(reference.portion_size_grams).to eq(250)
    expect(reference.calories_per_portion).to eq(450)
    expect(reference.proteins_per_portion).to eq(34.5)
    expect(reference.carbs_per_portion).to eq(48.25)
    expect(reference.fats_per_portion).to eq(11.75)
    expect(reference.portion_quantity).to eq(1)
  end

  it "ignores recipes that do not belong to the patient" do
    other_recipe = create(:recipe, patient: other_patient)

    result = described_class.run(
      meal: meal,
      patient: patient,
      description: "Almoço com @[Other](recipe:#{other_recipe.id})"
    )

    expect(result).to be_valid
    expect(meal.meal_recipe_references.reload).to be_empty
  end

  it "replaces existing references when the description changes" do
    create(:meal_recipe_reference, meal:, recipe:)
    second_recipe = create(:recipe, patient:, name: "Rice bowl")

    described_class.run!(
      meal: meal,
      patient: patient,
      description: "Jantar com @[Rice bowl](recipe:#{second_recipe.id})"
    )

    reference = meal.meal_recipe_references.sole
    expect(reference.recipe).to eq(second_recipe)
    expect(reference.recipe_name).to eq("Rice bowl")
  end

  it "keeps repeated mentions as separate references" do
    described_class.run!(
      meal: meal,
      patient: patient,
      description: "@[Chicken bowl](recipe:#{recipe.id}) e @[Chicken bowl](recipe:#{recipe.id})"
    )

    expect(meal.meal_recipe_references.count).to eq(2)
  end
end
