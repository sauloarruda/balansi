# frozen_string_literal: true

module BmiCalculations
  extend ActiveSupport::Concern

  BMI_CATEGORIES = [
    [ :underweight, 0, 18.5 ],
    [ :normal, 18.5, 25 ],
    [ :overweight, 25, 30 ],
    [ :obesity_1, 30, 35 ],
    [ :obesity_2, 35, 40 ],
    [ :obesity_3, 40, 60 ]
  ].freeze

  # BMI = weight (kg) / height (m)². Returns nil if weight or height missing.
  def bmi
    return nil if weight_kg.blank? || height_cm.blank?

    height_m = height_cm.to_d / 100
    (weight_kg.to_d / (height_m * height_m)).round(1)
  end

  # WHO categories: underweight (<18.5), normal (18.5–24.9), overweight (25–29.9),
  # obesity_1 (30–34.9), obesity_2 (35–39.9), obesity_3 (≥40).
  def bmi_category
    return nil if bmi.nil?

    b = bmi.to_d
    return :underweight if b < 18.5
    return :normal if b < 25
    return :overweight if b < 30
    return :obesity_1 if b < 35
    return :obesity_2 if b < 40

    :obesity_3
  end

  # Normal BMI weight range [min_kg, max_kg] for current height. Nil if height missing.
  def normal_bmi_weight_range
    return nil if height_cm.blank?

    height_m = height_cm.to_d / 100
    min_kg = (18.5 * height_m * height_m).round(1)
    max_kg = (24.9 * height_m * height_m).round(1)
    [min_kg, max_kg]
  end

  # Positive = kg to lose to reach normal max; negative = kg to gain to reach normal min; nil if normal or data missing.
  def weight_difference_to_normal_kg
    return nil if weight_kg.blank? || normal_bmi_weight_range.nil?

    min_kg, max_kg = normal_bmi_weight_range
    current = weight_kg.to_d
    return -(min_kg - current).round(1) if current < min_kg
    return (current - max_kg).round(1) if current > max_kg

    nil
  end

  # Weight (kg) ranges per BMI category for current height. For chart. Nil if height missing.
  # Returns Hash: { underweight: [0, 53.5], normal: [53.5, 72.0], ... }
  def bmi_category_weight_ranges
    return nil if height_cm.blank?

    h = height_cm.to_d / 100
    BMI_CATEGORIES.map do |cat, bmi_lo, bmi_hi|
      [ cat, [ (bmi_lo * h * h).round(1), (bmi_hi * h * h).round(1) ] ]
    end.to_h
  end

  # Max weight (kg) for chart scale. Ensures current weight fits and bar has sensible width.
  def bmi_chart_scale_max_kg
    return nil if height_cm.blank?

    ranges = bmi_category_weight_ranges
    return nil unless ranges

    max_from_ranges = ranges.values.map(&:last).max.to_f
    current = weight_kg.to_f
    [ max_from_ranges, (current * 1.15).ceil ].max
  end

  # Percentage position (0–100) of current weight on the chart scale. For marker placement.
  def bmi_chart_marker_position_percent
    return nil if weight_kg.blank?
    scale_max = bmi_chart_scale_max_kg
    return nil unless scale_max&.positive?

    pct = (weight_kg.to_f / scale_max) * 100
    [[pct, 0].max, 100].min
  end

  # Hex colors for each BMI category (for bar and legend).
  BMI_CATEGORY_HEX = {
    underweight: "#7dd3fc",
    normal: "#4ade80",
    overweight: "#facc15",
    obesity_1: "#fb923c",
    obesity_2: "#ea580c",
    obesity_3: "#ef4444"
  }.freeze

  # CSS linear-gradient string for the BMI bar (one element, all colors). Nil if no ranges.
  # Percentages rounded to 2 decimals so CSS is valid and compact.
  def bmi_chart_bar_gradient_css
    ranges = bmi_category_weight_ranges
    scale_max = bmi_chart_scale_max_kg
    return nil unless ranges && scale_max&.positive?

    stops = ranges.map do |cat, (lo, hi)|
      pct_lo = ((lo / scale_max) * 100).round(2)
      pct_hi = ((hi / scale_max) * 100).round(2)
      "#{BMI_CATEGORY_HEX[cat]} #{pct_lo}% #{pct_hi}%"
    end
    "linear-gradient(to right, #{stops.join(', ')})"
  end
end
