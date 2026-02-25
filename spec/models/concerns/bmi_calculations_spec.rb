# frozen_string_literal: true

require "rails_helper"

RSpec.describe BmiCalculations, type: :model do
  # Test via Patient which includes the concern
  let(:patient) { build(:patient, weight_kg: 70, height_cm: 170) }

  describe "#bmi_chart_scale_max_kg" do
    it "returns max kg for chart scale when height present" do
      expect(patient.bmi_chart_scale_max_kg).to be >= 72
      expect(patient.bmi_chart_scale_max_kg).to be >= (70 * 1.15)
    end

    it "returns nil when height missing" do
      p = build(:patient, weight_kg: 70, height_cm: nil)
      expect(p.bmi_chart_scale_max_kg).to be_nil
    end
  end

  describe "#bmi_chart_marker_position_percent" do
    it "returns 0–100 for current weight position on scale" do
      p = build(:patient, weight_kg: 70, height_cm: 170)
      percent = p.bmi_chart_marker_position_percent
      expect(percent).to be >= 0
      expect(percent).to be <= 100
    end

    it "returns nil when weight missing" do
      p = build(:patient, weight_kg: nil, height_cm: 170)
      expect(p.bmi_chart_marker_position_percent).to be_nil
    end
  end

  describe "#bmi_chart_bar_gradient_css" do
    it "returns a linear-gradient string with hex colors" do
      p = build(:patient, weight_kg: 70, height_cm: 170)
      css = p.bmi_chart_bar_gradient_css
      expect(css).to start_with("linear-gradient(to right,")
      expect(css).to include("#7dd3fc")
      expect(css).to include("#4ade80")
      expect(css).to include("#ef4444")
    end

    it "returns nil when height missing" do
      p = build(:patient, weight_kg: 70, height_cm: nil)
      expect(p.bmi_chart_bar_gradient_css).to be_nil
    end
  end
end
