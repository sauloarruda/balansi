require "rails_helper"

RSpec.describe Recipe, type: :model do
  describe "associations" do
    it "belongs to patient" do
      recipe = create(:recipe)
      expect(recipe.patient).to be_present
    end

    it "has many images" do
      recipe = create(:recipe)
      image = create(:image, recipe: recipe)

      expect(recipe.images).to include(image)
    end
  end

  describe "discard" do
    it "soft deletes recipes with discarded_at" do
      recipe = create(:recipe)

      recipe.discard!

      expect(recipe).to be_discarded
      expect(described_class.kept).not_to include(recipe)
      expect(described_class.find(recipe.id)).to eq(recipe)
    end
  end

  describe "validations" do
    it "is valid with required fields" do
      recipe = build(:recipe)
      expect(recipe).to be_valid
    end

    it "requires patient" do
      recipe = build(:recipe, patient: nil)
      expect(recipe).not_to be_valid
      expect(recipe.errors[:patient]).to be_present
    end

    it "requires name" do
      recipe = build(:recipe, name: nil)
      expect(recipe).not_to be_valid
      expect(recipe.errors[:name]).to be_present
    end

    it "requires ingredients" do
      recipe = build(:recipe, ingredients: nil)
      expect(recipe).not_to be_valid
      expect(recipe.errors[:ingredients]).to be_present
    end

    it "requires portion size greater than zero" do
      recipe = build(:recipe, portion_size_grams: 0)
      expect(recipe).not_to be_valid
      expect(recipe.errors[:portion_size_grams]).to be_present
    end

    it "allows recipes without macro values" do
      recipe = build(:recipe,
        calories: nil,
        proteins: nil,
        carbs: nil,
        fats: nil)

      expect(recipe).to be_valid
    end

    it "allows recipes without instructions" do
      recipe = build(:recipe, instructions: nil)
      expect(recipe).to be_valid
    end

    it "validates macro values are non-negative when present" do
      recipe = build(:recipe,
        calories: -1,
        proteins: -1,
        carbs: -1,
        fats: -1)

      expect(recipe).not_to be_valid
      expect(recipe.errors[:calories]).to be_present
      expect(recipe.errors[:proteins]).to be_present
      expect(recipe.errors[:carbs]).to be_present
      expect(recipe.errors[:fats]).to be_present
    end

    it "allows recipe macros with up to two decimal places" do
      recipe = build(:recipe, proteins: 10.25, carbs: 20.5, fats: 3.75)

      expect(recipe).to be_valid
    end

    it "rejects recipe macros with more than two decimal places" do
      recipe = build(:recipe, proteins: "10.255", carbs: "20.555", fats: "3.755")

      expect(recipe).not_to be_valid
      expect(recipe.errors[:proteins]).to include(I18n.t("activerecord.errors.messages.max_two_decimal_places"))
      expect(recipe.errors[:carbs]).to include(I18n.t("activerecord.errors.messages.max_two_decimal_places"))
      expect(recipe.errors[:fats]).to include(I18n.t("activerecord.errors.messages.max_two_decimal_places"))
    end
  end

  describe "per-portion helpers" do
    it "returns the macro values stored for one portion" do
      recipe = build(:recipe,
        portion_size_grams: 200,
        calories: 500,
        proteins: 80.5,
        carbs: 120.25,
        fats: 40.75)

      expect(recipe.calories_per_portion).to eq(500.0)
      expect(recipe.proteins_per_portion).to eq(80.5)
      expect(recipe.carbs_per_portion).to eq(120.25)
      expect(recipe.fats_per_portion).to eq(40.75)
    end

    it "calculates macro values proportionally for a gram amount" do
      recipe = build(:recipe,
        portion_size_grams: 200,
        calories: 300,
        proteins: 20,
        carbs: 30,
        fats: 10)

      expect(recipe.calories_for_grams(150)).to eq(225.0)
      expect(recipe.proteins_for_grams(150)).to eq(15.0)
      expect(recipe.carbs_for_grams(150)).to eq(22.5)
      expect(recipe.fats_for_grams(150)).to eq(7.5)
    end

    it "returns nil for missing macro values" do
      recipe = build(:recipe,
        calories: nil,
        proteins: nil,
        carbs: nil,
        fats: nil)

      expect(recipe.calories_per_portion).to be_nil
      expect(recipe.proteins_per_portion).to be_nil
      expect(recipe.carbs_per_portion).to be_nil
      expect(recipe.fats_per_portion).to be_nil
      expect(recipe.calories_for_grams(150)).to be_nil
    end
  end
end
