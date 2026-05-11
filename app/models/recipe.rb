class Recipe < ApplicationRecord
  CALORIES_MAX = 50_000
  MACROS_MAX = 10_000

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
end
