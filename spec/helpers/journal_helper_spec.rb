require "rails_helper"

RSpec.describe JournalHelper, type: :helper do
  describe "#caloric_balance_visual_status" do
    let(:burned_calories) { 2289 }
    let(:daily_calorie_goal) { 1300 }

    it "returns weight_loss when consumed is goal-aligned and in strong deficit" do
      expect(helper.caloric_balance_visual_status(1350, burned_calories, daily_calorie_goal)).to eq("weight_loss")
    end

    it "returns below_goal when consumed is below 90% of goal" do
      expect(helper.caloric_balance_visual_status(1100, burned_calories, daily_calorie_goal)).to eq("below_goal")
    end

    it "returns maintenance when consumed is within maintenance expenditure range" do
      expect(helper.caloric_balance_visual_status(2100, burned_calories, daily_calorie_goal)).to eq("maintenance")
    end

    it "returns weight_gain when consumed is above 115% of burned calories" do
      expect(helper.caloric_balance_visual_status(2700, burned_calories, daily_calorie_goal)).to eq("weight_gain")
    end
  end

  describe "#balance_message_key" do
    it "maps message keys by status" do
      expect(helper.balance_message_key("maintenance")).to eq(".maintenance")
      expect(helper.balance_message_key("weight_gain")).to eq(".weight_gain")
      expect(helper.balance_message_key("weight_loss")).to eq(".weight_loss")
      expect(helper.balance_message_key("below_goal")).to eq(".below_goal")
    end
  end

  describe "#format_meal_description" do
    it "renders recipe mentions as visual chips" do
      patient = create(:patient)
      recipe = create(:recipe, patient: patient, name: "Bolo de banana", portion_size_grams: 180)
      allow(helper).to receive(:current_patient_recipes).and_return(patient.recipes)

      html = helper.format_meal_description("Comi @[Bolo de banana](recipe:#{recipe.id}) hoje")

      expect(html).to include("Comi ")
      expect(html).to include("Bolo de banana (180g)")
      expect(html).to include("recipe-mention-chip")
      expect(html).to include(" hoje")
      expect(html).not_to include("@[Bolo de banana](recipe:#{recipe.id})")
    end

    it "renders recipe reference tooltip details when snapshots are provided" do
      patient = create(:patient)
      recipe = create(:recipe, patient: patient, name: "Bolo de banana", calories: 320, proteins: 8, carbs: 52, fats: 9)
      meal = create(:meal, journal: create(:journal, patient: patient), description: "Comi @[Bolo de banana](recipe:#{recipe.id})")
      reference = create(:meal_recipe_reference, meal: meal, recipe: recipe)

      html = helper.format_meal_description(
        meal.description,
        recipe_references: [ reference ],
        patient_id: patient.id
      )

      expect(html).to include("data-controller=\"popover-tooltip\"")
      expect(html).to include("320")
      expect(html).to include("macro-ring")
      expect(html).to include(helper.patient_recipe_path(recipe))
    end

    it "renders discarded recipe snapshots without linking to the recipe" do
      patient = create(:patient)
      recipe = create(:recipe, patient: patient, name: "Bolo de banana", calories: 320, proteins: 8, carbs: 52, fats: 9)
      meal = create(:meal, journal: create(:journal, patient: patient), description: "Comi @[Bolo de banana](recipe:#{recipe.id})")
      reference = create(:meal_recipe_reference, meal: meal, recipe: recipe)
      recipe.discard!

      html = helper.format_meal_description(
        meal.description,
        recipe_references: [ reference ],
        patient_id: patient.id
      )

      expect(html).to include(I18n.t("meals.recipe_references.deleted_recipe"))
      expect(html).to include("320")
      expect(html).not_to include(helper.patient_recipe_path(recipe))
    end

    it "escapes plain text and recipe names" do
      html = helper.format_meal_description("<script>x</script> @[Bolo <caseiro>](recipe:123)")

      expect(html).to include("&lt;script&gt;x&lt;/script&gt;")
      expect(html).to include("Bolo &lt;caseiro&gt;")
      expect(html).not_to include("<script>")
    end

    it "keeps descriptions without recipe mentions readable" do
      expect(helper.format_meal_description("Arroz e feijão")).to eq("Arroz e feijão")
    end
  end

  describe "#meal_recipe_mention_data" do
    it "returns portion metadata for mentioned recipes in scope" do
      patient = create(:patient)
      recipe = create(:recipe, patient: patient, name: "Iogurte", portion_size_grams: 200)
      create(:recipe, name: "Private", portion_size_grams: 300)
      allow(helper).to receive(:current_patient_recipes).and_return(patient.recipes)

      data = helper.meal_recipe_mention_data("Comi @[Iogurte](recipe:#{recipe.id})")

      expect(data).to eq([
        {
          id: recipe.id,
          portion_size_grams: 200.0,
          calories_per_portion: 400.0,
          proteins_per_portion: 30.25,
          carbs_per_portion: 45.12,
          fats_per_portion: 12.38
        }
      ])
    end

    it "does not return portion metadata for recipes owned by another patient" do
      patient = create(:patient)
      other_patient = create(:patient)
      other_recipe = create(:recipe, patient: other_patient, name: "Iogurte", portion_size_grams: 200)
      allow(helper).to receive(:current_patient_recipes).and_return(patient.recipes)

      data = helper.meal_recipe_mention_data("Comi @[Iogurte](recipe:#{other_recipe.id})")

      expect(data).to eq([])
    end

    it "returns no portion metadata without a current patient" do
      recipe = create(:recipe, name: "Iogurte", portion_size_grams: 200)
      allow(helper).to receive(:current_patient_recipes).and_return(Recipe.none)

      data = helper.meal_recipe_mention_data("Comi @[Iogurte](recipe:#{recipe.id})")

      expect(data).to eq([])
    end
  end

  describe "#recipe_mention_data" do
    it "returns portion metadata for mentioned recipes in scope" do
      patient = create(:patient)
      recipe = create(:recipe, patient: patient, name: "Iogurte", portion_size_grams: 200)
      allow(helper).to receive(:current_patient_recipes).and_return(patient.recipes)

      data = helper.recipe_mention_data("Comi @[Iogurte](recipe:#{recipe.id})")

      expect(data).to eq([
        {
          id: recipe.id,
          portion_size_grams: 200.0,
          calories_per_portion: 400.0,
          proteins_per_portion: 30.25,
          carbs_per_portion: 45.12,
          fats_per_portion: 12.38
        }
      ])
    end
  end
end
