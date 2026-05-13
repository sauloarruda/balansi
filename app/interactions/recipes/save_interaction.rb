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
    return true if nutrition_manually_provided?

    result = Recipes::AnalyzeNutritionInteraction.run(
      recipe: recipe,
      user_id: user.id,
      user_language: user.language.presence || "pt",
      persist: false
    )

    return true if result.valid?

    copy_analysis_errors(result)
    false
  end

  def nutrition_manually_provided?
    Recipes::AnalyzeNutritionInteraction::NUTRITION_ATTRIBUTES.all? do |attribute|
      recipe.public_send(attribute).present?
    end
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
end
