require "rails_helper"

RSpec.describe Recipe, type: :model do
  describe "associations" do
    it "belongs to patient" do
      recipe = create(:recipe)
      expect(recipe.patient).to be_present
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

    it "requires yield portions greater than or equal to one" do
      recipe = build(:recipe, yield_portions: 0)
      expect(recipe).not_to be_valid
      expect(recipe.errors[:yield_portions]).to be_present
    end

    it "allows recipes without macro totals" do
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

    it "validates macro totals are non-negative when present" do
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
    it "calculates macro values from totals and yield" do
      recipe = build(:recipe,
        yield_portions: 4,
        calories: 1_000,
        proteins: 80.5,
        carbs: 120.25,
        fats: 40.75)

      expect(recipe.calories_per_portion).to eq(250.0)
      expect(recipe.proteins_per_portion).to eq(20.125)
      expect(recipe.carbs_per_portion).to eq(30.0625)
      expect(recipe.fats_per_portion).to eq(10.1875)
    end

    it "returns nil for missing macro totals" do
      recipe = build(:recipe,
        calories: nil,
        proteins: nil,
        carbs: nil,
        fats: nil)

      expect(recipe.calories_per_portion).to be_nil
      expect(recipe.proteins_per_portion).to be_nil
      expect(recipe.carbs_per_portion).to be_nil
      expect(recipe.fats_per_portion).to be_nil
    end
  end
end
