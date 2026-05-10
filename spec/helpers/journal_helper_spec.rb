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
end
