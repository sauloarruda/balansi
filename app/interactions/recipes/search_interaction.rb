class Recipes::SearchInteraction < ActiveInteraction::Base
  MAX_RESULTS = 10
  RECENT_RESULTS = 5

  object :patient, class: Patient
  string :query, default: ""
  string :recipe_id, default: ""
  boolean :recent, default: false

  def execute
    return recipe_by_id if recipe_id.present?

    normalized_query = normalized_search_text(query)
    return recent_recipes if normalized_query.blank? && recent
    return ::Recipe.none if normalized_query.blank?

    patient.recipes.kept
      .includes(images: { file_attachment: :blob })
      .order(:name, :id)
      .select { |recipe| normalized_search_text(recipe.name).include?(normalized_query) }
      .first(MAX_RESULTS)
  end

  private

  def recipe_by_id
    patient.recipes.kept
      .includes(images: { file_attachment: :blob })
      .where(id: recipe_id)
      .limit(1)
  end

  def recent_recipes
    patient.recipes.kept
      .includes(images: { file_attachment: :blob })
      .order(updated_at: :desc, id: :desc)
      .limit(RECENT_RESULTS)
  end

  def normalized_search_text(value)
    ActiveSupport::Inflector.transliterate(value.to_s).downcase.strip
  end
end
