class Recipe < ApplicationRecord
  CALORIES_MAX = 50_000
  MACROS_MAX = 10_000
  MACRO_ATTRIBUTES = %i[proteins carbs fats].freeze

  belongs_to :patient

  validates :name, presence: true
  validates :ingredients, presence: true
  validates :yield_portions, numericality: { greater_than_or_equal_to: 1 }
  validates :calories,
    numericality: { greater_than_or_equal_to: 0, less_than: CALORIES_MAX },
    allow_nil: true
  validates :proteins,
    :carbs,
    :fats,
    numericality: { greater_than_or_equal_to: 0, less_than: MACROS_MAX },
    allow_nil: true
  validate :macro_decimal_places

  def calories_per_portion
    per_portion(calories)
  end

  def proteins_per_portion
    per_portion(proteins)
  end

  def carbs_per_portion
    per_portion(carbs)
  end

  def fats_per_portion
    per_portion(fats)
  end

  private

  def per_portion(total)
    return nil if total.nil? || yield_portions.blank? || yield_portions.zero?

    total.to_f / yield_portions
  end

  def macro_decimal_places
    MACRO_ATTRIBUTES.each do |attribute|
      raw_value = public_send("#{attribute}_before_type_cast")
      next if raw_value.blank?

      value = raw_value.respond_to?(:to_s) && raw_value.is_a?(BigDecimal) ? raw_value.to_s("F") : raw_value.to_s
      next if value.match?(/\A-?\d+(\.\d{1,2})?\z/)

      errors.add(attribute, :max_two_decimal_places)
    end
  end
end
