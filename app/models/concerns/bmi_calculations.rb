# frozen_string_literal: true

module BmiCalculations
  extend ActiveSupport::Concern

  # Upper bound for obesity_3 in chart (category is open-ended above 40).
  BMI_CHART_OBESITY3_CAP = 60

  BMI_CATEGORIES = [
    [ :underweight, 0,    18.5             ],
    [ :normal,      18.5, 25               ],
    [ :overweight,  25,   30               ],
    [ :obesity_1,   30,   35               ],
    [ :obesity_2,   35,   40               ],
    [ :obesity_3,   40,   Float::INFINITY  ]
  ].freeze

  # Hex colors for each BMI category (for bar and legend).
  BMI_CATEGORY_HEX = {
    underweight: "#7dd3fc",
    normal:      "#4ade80",
    overweight:  "#facc15",
    obesity_1:   "#fb923c",
    obesity_2:   "#ea580c",
    obesity_3:   "#ef4444"
  }.freeze

  # BMI = weight (kg) / height (m)². Returns nil if weight or height missing.
  def bmi
    return nil if weight_kg.blank? || height_cm.blank?

    (weight_kg.to_d / height_m**2).round(1)
  end

  # WHO categories derived from BMI_CATEGORIES.
  def bmi_category
    return nil if bmi.nil?

    b = bmi.to_d
    BMI_CATEGORIES.find { |_, lo, hi| b >= lo && b < hi }&.first
  end

  # Normal BMI weight range [min_kg, max_kg] for current height. Nil if height missing.
  def normal_bmi_weight_range
    bmi_category_weight_ranges&.fetch(:normal)
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

    h = height_m
    BMI_CATEGORIES.map do |cat, bmi_lo, bmi_hi|
      hi_capped = bmi_hi == Float::INFINITY ? BMI_CHART_OBESITY3_CAP : bmi_hi
      [ cat, [ (bmi_lo * h * h).round(1), (hi_capped * h * h).round(1) ] ]
    end.to_h
  end

  # Max weight (kg) for chart scale. Ensures current weight fits and bar has sensible width.
  def bmi_chart_scale_max_kg
    return nil if height_cm.blank?

    ranges = bmi_category_weight_ranges
    max_from_ranges = ranges.values.map(&:last).max.to_f
    [ max_from_ranges, (weight_kg.to_f * 1.15).ceil ].max
  end

  # Percentage position (0–100) of current weight on the chart scale. For marker placement.
  def bmi_chart_marker_position_percent
    return nil if weight_kg.blank?

    scale_max = bmi_chart_scale_max_kg
    return nil unless scale_max&.positive?

    pct = (weight_kg.to_f / scale_max) * 100
    [ [ pct, 0 ].max, 100 ].min
  end

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

  private

  def height_m
    height_cm.to_d / 100
  end
end
