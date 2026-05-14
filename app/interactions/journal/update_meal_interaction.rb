class Journal::UpdateMealInteraction < ActiveInteraction::Base
  Result = Struct.new(:meal, :analysis_errors, keyword_init: true)

  object :meal, class: Meal
  object :patient, class: Patient
  object :user, class: User
  object :attributes, class: ActionController::Parameters
  boolean :confirm, default: false
  boolean :reprocess, default: false

  def execute
    if reprocess
      reprocess_meal
    else
      update_meal
    end

    Result.new(meal: meal, analysis_errors: analysis_errors)
  end

  private

  attr_reader :analysis_errors

  def update_meal
    Meal.transaction do
      unless meal.update(update_attributes)
        copy_meal_errors_to_interaction
        raise ActiveRecord::Rollback
      end

      meal.confirm! if confirm
    end
  end

  def reprocess_meal
    previous_status = meal.status

    Meal.transaction do
      unless meal.update(reprocess_attributes)
        copy_meal_errors_to_interaction
        raise ActiveRecord::Rollback
      end

      sync_recipe_references
      meal.update!(status: :pending_llm)
    end

    return if errors.any?

    analyze_reprocessed_meal(previous_status)
  end

  def analyze_reprocessed_meal(previous_status)
    result = Journal::AnalyzeMealInteraction.run(
      meal: meal,
      user_id: user.id,
      description: meal.description,
      meal_type: meal.meal_type,
      user_language: user.language
    )

    return if result.valid?

    @analysis_errors = result.errors
    meal.update!(status: previous_status)
  end

  def sync_recipe_references
    Journal::ResolveRecipeReferencesInteraction.run!(
      meal: meal,
      patient: patient,
      description: meal.description
    )
  end

  def update_attributes
    attributes.to_h.symbolize_keys.slice(
      :meal_type,
      :description,
      :calories,
      :proteins,
      :carbs,
      :fats,
      :gram_weight
    )
  end

  def reprocess_attributes
    attributes.to_h.symbolize_keys.slice(:meal_type, :description)
  end

  def copy_meal_errors_to_interaction
    meal.errors.each do |error|
      errors.add(error.attribute, error.message)
    end
  end
end
