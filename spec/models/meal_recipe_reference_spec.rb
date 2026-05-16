require "rails_helper"

RSpec.describe MealRecipeReference, type: :model do
  let(:patient) { create(:patient, user: create(:user)) }
  let(:journal) { create(:journal, patient:, date: Date.new(2026, 2, 11)) }
  let(:meal) { Meal.create!(journal:, meal_type: "lunch", description: "Almoço") }
  let(:recipe) { create(:recipe, patient:) }

  it "is valid with a meal and recipe snapshot" do
    reference = described_class.new(
      meal: meal,
      recipe: recipe,
      recipe_name: recipe.name,
      portion_size_grams: recipe.portion_size_grams,
      calories_per_portion: recipe.calories_per_portion,
      proteins_per_portion: recipe.proteins_per_portion,
      carbs_per_portion: recipe.carbs_per_portion,
      fats_per_portion: recipe.fats_per_portion
    )

    expect(reference).to be_valid
  end

  it "keeps the historical snapshot when the recipe changes" do
    reference = create(:meal_recipe_reference, meal:, recipe:)

    recipe.update!(name: "Updated bowl", calories: 500, proteins: 40)

    expect(reference.reload.recipe_name).to eq("Chicken bowl")
    expect(reference.calories_per_portion).to eq(400)
    expect(reference.proteins_per_portion).to eq(30.25)
  end

  it "keeps snapshot fields when the recipe is deleted" do
    reference = create(:meal_recipe_reference, meal:, recipe:)

    recipe.destroy!

    expect(reference.reload).to be_valid
    expect(reference.recipe).to be_nil
    expect(reference.recipe_name).to eq("Chicken bowl")
  end

  it "keeps the recipe association when the recipe is discarded" do
    reference = create(:meal_recipe_reference, meal:, recipe:)

    recipe.discard!

    expect(reference.reload).to be_valid
    expect(reference.recipe).to eq(recipe)
    expect(reference.recipe).to be_discarded
    expect(reference.recipe_name).to eq("Chicken bowl")
  end
end
