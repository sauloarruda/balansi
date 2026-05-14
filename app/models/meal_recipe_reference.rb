class MealRecipeReference < ApplicationRecord
  belongs_to :meal
  belongs_to :recipe, optional: true

  validates :recipe_name, presence: true
  validates :portion_size_grams, numericality: { greater_than: 0, less_than: Recipe::PORTION_SIZE_GRAMS_MAX }
  validates :calories_per_portion,
    numericality: { greater_than_or_equal_to: 0, less_than: Recipe::CALORIES_MAX },
    allow_nil: true
  validates :proteins_per_portion,
    :carbs_per_portion,
    :fats_per_portion,
    numericality: { greater_than_or_equal_to: 0, less_than: Recipe::MACROS_MAX },
    allow_nil: true
  validates :portion_quantity, numericality: { greater_than: 0, less_than: 10_000 }
end
