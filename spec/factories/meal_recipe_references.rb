FactoryBot.define do
  factory :meal_recipe_reference do
    association :meal
    association :recipe
    recipe_name { recipe.name }
    portion_size_grams { recipe.portion_size_grams }
    calories_per_portion { recipe.calories_per_portion }
    proteins_per_portion { recipe.proteins_per_portion }
    carbs_per_portion { recipe.carbs_per_portion }
    fats_per_portion { recipe.fats_per_portion }
    portion_quantity { 1 }
  end
end
