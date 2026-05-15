class Recipes::SearchInteraction < ActiveInteraction::Base
  MAX_RESULTS = 10
  RECENT_RESULTS = 5

  object :patient, class: Patient
  string :query, default: ""
  boolean :recent, default: false

  def execute
    normalized_query = query.strip
    return recent_recipes if normalized_query.blank? && recent
    return ::Recipe.none if normalized_query.blank?

    escaped_query = ActiveRecord::Base.sanitize_sql_like(normalized_query)

    patient.recipes.kept
      .includes(images: { file_attachment: :blob })
      .where(::Recipe.arel_table[:name].matches("%#{escaped_query}%"))
      .order(:name, :id)
      .limit(MAX_RESULTS)
  end

  private

  def recent_recipes
    patient.recipes.kept
      .includes(images: { file_attachment: :blob })
      .order(updated_at: :desc, id: :desc)
      .limit(RECENT_RESULTS)
  end
end
