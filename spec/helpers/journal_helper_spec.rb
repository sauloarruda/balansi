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

      expect(data).to eq([ { id: recipe.id, portion_size_grams: 200.0 } ])
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
end
