require "rails_helper"

RSpec.describe Recipes::SearchInteraction, type: :interaction do
  let(:patient) { create(:patient) }

  it "returns current patient recipes matching the name prefix" do
    matching_recipe = create(:recipe, patient: patient, name: "Bolo de banana")
    create(:recipe, patient: patient, name: "Panqueca de banana")
    create(:recipe, name: "Bolo privado")

    result = described_class.run!(patient: patient, query: "Bolo")

    expect(result).to contain_exactly(matching_recipe)
  end

  it "does not return discarded recipes" do
    matching_recipe = create(:recipe, patient: patient, name: "Bolo de banana")
    discarded_recipe = create(:recipe, patient: patient, name: "Bolo antigo")
    discarded_recipe.discard!

    result = described_class.run!(patient: patient, query: "Bolo")

    expect(result).to contain_exactly(matching_recipe)
  end

  it "returns a current patient recipe by id" do
    recipe = create(:recipe, patient: patient, name: "Created recipe")
    create(:recipe, patient: patient, name: "Other recipe")

    result = described_class.run!(patient: patient, recipe_id: recipe.id.to_s)

    expect(result).to contain_exactly(recipe)
  end

  it "does not return other patient recipes by id" do
    other_recipe = create(:recipe, name: "Private recipe")

    result = described_class.run!(patient: patient, recipe_id: other_recipe.id.to_s)

    expect(result).to be_empty
  end

  it "does not return discarded recipes by id" do
    recipe = create(:recipe, patient: patient)
    recipe.discard!

    result = described_class.run!(patient: patient, recipe_id: recipe.id.to_s)

    expect(result).to be_empty
  end

  it "returns current patient recipes matching any part of the name" do
    matching_recipe = create(:recipe, patient: patient, name: "Carne com legumes")
    create(:recipe, patient: patient, name: "Carne assada")

    result = described_class.run!(patient: patient, query: "legumes")

    expect(result).to contain_exactly(matching_recipe)
  end

  it "strips blank space around the query" do
    recipe = create(:recipe, patient: patient, name: "Bolo de cenoura")

    result = described_class.run!(patient: patient, query: "  Bolo  ")

    expect(result).to contain_exactly(recipe)
  end

  it "limits results to ten recipes ordered by name" do
    11.times do |index|
      create(:recipe, patient: patient, name: "Bolo #{index.to_s.rjust(2, "0")}")
    end

    result = described_class.run!(patient: patient, query: "Bolo")

    expect(result.map(&:name)).to eq(
      10.times.map { |index| "Bolo #{index.to_s.rjust(2, "0")}" }
    )
  end

  it "returns an empty relation for blank queries" do
    create(:recipe, patient: patient, name: "Bolo de cenoura")

    result = described_class.run!(patient: patient, query: "")

    expect(result).to be_empty
  end

  it "returns five recently updated recipes for explicit recent blank searches" do
    older_recipe = create(:recipe, patient: patient, name: "Older")
    recipes = 6.times.map do |index|
      create(:recipe, patient: patient, name: "Recent #{index}", updated_at: index.minutes.from_now)
    end
    create(:recipe, name: "Other patient", updated_at: 1.hour.from_now)

    result = described_class.run!(patient: patient, query: "", recent: true)

    expect(result).to eq(recipes.last(5).reverse)
    expect(result).not_to include(older_recipe)
  end

  it "does not return discarded recipes in recent searches" do
    kept_recipe = create(:recipe, patient: patient, name: "Kept", updated_at: 1.minute.from_now)
    discarded_recipe = create(:recipe, patient: patient, name: "Discarded", updated_at: 2.minutes.from_now)
    discarded_recipe.discard!

    result = described_class.run!(patient: patient, query: "", recent: true)

    expect(result).to contain_exactly(kept_recipe)
  end
end
