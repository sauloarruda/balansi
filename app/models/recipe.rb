class Recipe < ApplicationRecord
  CALORIES_MAX = 50_000
  MACROS_MAX = 10_000
  PORTION_SIZE_GRAMS_MAX = 50_000
  MACRO_ATTRIBUTES = %i[proteins carbs fats].freeze

  belongs_to :patient
  has_many :images, -> { order(:position, :id) }, dependent: :destroy

  validates :name, presence: true
  validates :ingredients, presence: true
  validates :portion_size_grams,
    numericality: { greater_than: 0, less_than: PORTION_SIZE_GRAMS_MAX }
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
    normalized_macro(calories)
  end

  def proteins_per_portion
    normalized_macro(proteins)
  end

  def carbs_per_portion
    normalized_macro(carbs)
  end

  def fats_per_portion
    normalized_macro(fats)
  end

  def calories_for_grams(grams)
    macro_for_grams(calories, grams)
  end

  def proteins_for_grams(grams)
    macro_for_grams(proteins, grams)
  end

  def carbs_for_grams(grams)
    macro_for_grams(carbs, grams)
  end

  def fats_for_grams(grams)
    macro_for_grams(fats, grams)
  end

  private

  def normalized_macro(value)
    value&.to_f
  end

  def macro_for_grams(total, grams)
    return nil if total.nil? || grams.blank? || portion_size_grams.blank? || portion_size_grams.zero?

    total.to_f * grams.to_f / portion_size_grams.to_f
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
