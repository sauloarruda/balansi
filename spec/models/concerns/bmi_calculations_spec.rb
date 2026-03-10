# frozen_string_literal: true

require "rails_helper"

RSpec.describe BmiCalculations, type: :model do
  # 70 kg / (1.70 m)² = 24.2 BMI (normal)
  let(:patient) { build(:patient, weight_kg: 70, height_cm: 170) }

  describe "#bmi" do
    it "calculates correctly" do
      expect(patient.bmi).to eq(24.2)
    end

    it "returns nil when weight missing" do
      expect(build(:patient, weight_kg: nil, height_cm: 170).bmi).to be_nil
    end

    it "returns nil when height missing" do
      expect(build(:patient, weight_kg: 70, height_cm: nil).bmi).to be_nil
    end
  end

  describe "#bmi_category" do
    it "returns nil when bmi cannot be calculated" do
      expect(build(:patient, weight_kg: nil, height_cm: 170).bmi_category).to be_nil
    end

    {
      underweight: 45,
      normal:      70,
      overweight:  85,
      obesity_1:   95,
      obesity_2:   110,
      obesity_3:   125
    }.each do |category, weight|
      it "returns #{category} for #{weight} kg at 170 cm" do
        p = build(:patient, weight_kg: weight, height_cm: 170)
        expect(p.bmi_category).to eq(category)
      end
    end

    it "returns normal at exact lower boundary (18.5)" do
      # weight for BMI 18.5 at 170 cm = 18.5 * 1.70² = 53.465 kg
      p = build(:patient, weight_kg: 53.465, height_cm: 170)
      expect(p.bmi_category).to eq(:normal)
    end

    it "returns overweight at exact boundary (25.0)" do
      # weight for BMI 25.0 at 170 cm = 25.0 * 1.70² = 72.25 kg
      p = build(:patient, weight_kg: 72.25, height_cm: 170)
      expect(p.bmi_category).to eq(:overweight)
    end
  end

  describe "#normal_bmi_weight_range" do
    it "returns [min_kg, max_kg] matching the normal BMI category range" do
      min_kg, max_kg = patient.normal_bmi_weight_range
      expect(min_kg).to eq(53.5)   # 18.5 * 1.70²
      expect(max_kg).to eq(72.3)   # 25.0 * 1.70²
    end

    it "returns nil when height missing" do
      expect(build(:patient, weight_kg: 70, height_cm: nil).normal_bmi_weight_range).to be_nil
    end
  end

  describe "#weight_difference_to_normal_kg" do
    it "returns nil when patient is in normal range" do
      expect(patient.weight_difference_to_normal_kg).to be_nil
    end

    it "returns positive kg to lose when overweight" do
      p = build(:patient, weight_kg: 85, height_cm: 170)
      expect(p.weight_difference_to_normal_kg).to be > 0
    end

    it "returns negative kg to gain when underweight" do
      p = build(:patient, weight_kg: 45, height_cm: 170)
      expect(p.weight_difference_to_normal_kg).to be < 0
    end

    it "returns nil when weight missing" do
      expect(build(:patient, weight_kg: nil, height_cm: 170).weight_difference_to_normal_kg).to be_nil
    end
  end

  describe "#bmi_category_weight_ranges" do
    subject(:ranges) { patient.bmi_category_weight_ranges }

    it "returns a hash with all 6 categories" do
      expect(ranges.keys).to eq(%i[underweight normal overweight obesity_1 obesity_2 obesity_3])
    end

    it "each range is [lo, hi] with lo < hi" do
      ranges.each_value do |(lo, hi)|
        expect(lo).to be < hi
      end
    end

    it "caps obesity_3 at BMI_CHART_OBESITY3_CAP instead of infinity" do
      _, hi = ranges[:obesity_3]
      expect(hi).to be_finite
      expect(hi).to eq((BmiCalculations::BMI_CHART_OBESITY3_CAP * 1.70 * 1.70).round(1))
    end

    it "returns nil when height missing" do
      expect(build(:patient, weight_kg: 70, height_cm: nil).bmi_category_weight_ranges).to be_nil
    end
  end

  describe "#bmi_chart_scale_max_kg" do
    it "returns value >= max of weight ranges" do
      expect(patient.bmi_chart_scale_max_kg).to be >= patient.bmi_category_weight_ranges.values.map(&:last).max
    end

    it "returns value >= 115% of current weight" do
      expect(patient.bmi_chart_scale_max_kg).to be >= (70 * 1.15)
    end

    it "returns nil when height missing" do
      expect(build(:patient, weight_kg: 70, height_cm: nil).bmi_chart_scale_max_kg).to be_nil
    end
  end

  describe "#bmi_chart_marker_position_percent" do
    it "returns value between 0 and 100" do
      pct = patient.bmi_chart_marker_position_percent
      expect(pct).to be >= 0
      expect(pct).to be <= 100
    end

    it "returns nil when weight missing" do
      expect(build(:patient, weight_kg: nil, height_cm: 170).bmi_chart_marker_position_percent).to be_nil
    end
  end

  describe "#bmi_chart_bar_gradient_css" do
    it "returns a linear-gradient with all category hex colors" do
      css = patient.bmi_chart_bar_gradient_css
      expect(css).to start_with("linear-gradient(to right,")
      BmiCalculations::BMI_CATEGORY_HEX.each_value do |hex|
        expect(css).to include(hex)
      end
    end

    it "returns nil when height missing" do
      expect(build(:patient, weight_kg: 70, height_cm: nil).bmi_chart_bar_gradient_css).to be_nil
    end
  end
end
