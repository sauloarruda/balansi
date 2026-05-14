class Journal::CreateMealInteraction < ActiveInteraction::Base
  Result = Struct.new(:meal, :journal, :analysis_errors, keyword_init: true)

  object :patient, class: Patient
  object :user, class: User
  object :attributes, class: ActionController::Parameters
  date :journal_date

  def execute
    create_meal_with_references
    analyze_meal if errors.empty?

    Result.new(meal: meal, journal: journal, analysis_errors: analysis_errors)
  end

  private

  attr_reader :meal, :journal, :analysis_errors

  def create_meal_with_references
    Meal.transaction do
      @journal = patient.journals.find_or_create_by!(date: journal_date)
      @meal = journal.meals.build(meal_attributes)
      meal.status = :pending_llm

      unless meal.save
        copy_meal_errors_to_interaction
        raise ActiveRecord::Rollback
      end

      sync_recipe_references
    end
  end

  def analyze_meal
    result = Journal::AnalyzeMealInteraction.run(
      meal: meal,
      user_id: user.id,
      description: meal.description,
      meal_type: meal.meal_type,
      user_language: user.language
    )

    @analysis_errors = result.errors unless result.valid?
  end

  def sync_recipe_references
    Journal::ResolveRecipeReferencesInteraction.run!(
      meal: meal,
      patient: patient,
      description: meal.description
    )
  end

  def meal_attributes
    attributes.to_h.symbolize_keys.slice(:meal_type, :description)
  end

  def copy_meal_errors_to_interaction
    meal.errors.each do |error|
      errors.add(error.attribute, error.message)
    end
  end
end
