class Recipes::SaveInteraction < ActiveInteraction::Base
  object :recipe, class: Recipe
  object :user, class: User
  object :attributes, class: ActionController::Parameters
  array :images, default: []
  boolean :calculate_macros_with_ai, default: true

  def execute
    saved = false

    Recipe.transaction do
      recipe.assign_attributes(recipe_attributes)

      unless recipe.valid?
        copy_recipe_errors_to_interaction
        raise ActiveRecord::Rollback
      end

      raise ActiveRecord::Rollback unless analyze_recipe_nutrition

      recipe.save!
      attach_images
      saved = true
    end

    recipe if saved
  end

  private

  def recipe_attributes
    attributes.to_h.symbolize_keys
  end

  def analyze_recipe_nutrition
    return true unless calculate_macros_with_ai

    result = Recipes::AnalyzeNutritionInteraction.run(
      recipe: recipe,
      user_id: user.id,
      user_language: user.language.presence || "pt",
      recipe_context: recipe_context,
      persist: false,
      force: true
    )

    return true if result.valid?

    copy_analysis_errors(result)
    false
  end

  def attach_images
    images.compact_blank.each.with_index(recipe.images.count) do |uploaded_file, position|
      recipe.images.create!(file: uploaded_file, position: position)
    end
  end

  def copy_recipe_errors_to_interaction
    recipe.errors.each do |error|
      errors.add(error.attribute, error.message)
    end
  end

  def copy_analysis_errors(result)
    result.errors.full_messages.each do |message|
      recipe.errors.add(:base, message)
      errors.add(:base, message)
    end
  end

  def recipe_context
    recipe_ids = recipe.mentioned_recipe_ids.reject { |recipe_id| recipe_id == recipe.id }
    return [] if recipe_ids.empty?

    recipes_by_id = recipe.patient.recipes.kept.where(id: recipe_ids).index_by(&:id)

    recipe_ids.filter_map do |recipe_id|
      referenced_recipe = recipes_by_id[recipe_id]
      next unless referenced_recipe

      {
        recipe_name: referenced_recipe.name,
        portion_size_grams: referenced_recipe.portion_size_grams.to_f,
        calories_per_portion: referenced_recipe.calories&.to_f,
        proteins_per_portion: referenced_recipe.proteins&.to_f,
        carbs_per_portion: referenced_recipe.carbs&.to_f,
        fats_per_portion: referenced_recipe.fats&.to_f
      }
    end
  end
end
