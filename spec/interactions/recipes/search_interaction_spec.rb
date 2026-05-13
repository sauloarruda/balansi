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
end
