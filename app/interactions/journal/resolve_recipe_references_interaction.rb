class Journal::ResolveRecipeReferencesInteraction < ActiveInteraction::Base
  object :meal, class: Meal
  object :patient, class: Patient
  string :description, default: ""

  def execute
    mentions = recipe_mentions

    MealRecipeReference.transaction do
      meal.meal_recipe_references.destroy_all
      create_references(mentions) if mentions.any?
    end

    meal.meal_recipe_references.reload
  end

  private

  def recipe_mentions
    description.to_s.scan(Recipe::MENTION_PATTERN).map do |(_name, recipe_id)|
      recipe_id.to_i
    end
  end

  def create_references(recipe_ids)
    recipes_by_id = patient.recipes.where(id: recipe_ids).index_by(&:id)

    recipe_ids.each do |recipe_id|
      recipe = recipes_by_id[recipe_id]
      next unless recipe

      meal.meal_recipe_references.create!(snapshot_attributes_for(recipe))
    end
  end

  def snapshot_attributes_for(recipe)
    {
      recipe: recipe,
      recipe_name: recipe.name,
      portion_size_grams: recipe.portion_size_grams,
      calories_per_portion: recipe.calories_per_portion,
      proteins_per_portion: recipe.proteins_per_portion,
      carbs_per_portion: recipe.carbs_per_portion,
      fats_per_portion: recipe.fats_per_portion
    }
  end
end
