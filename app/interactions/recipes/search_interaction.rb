class Recipes::SearchInteraction < ActiveInteraction::Base
  MAX_RESULTS = 10

  object :patient, class: Patient
  string :query, default: ""

  def execute
    normalized_query = query.strip
    return ::Recipe.none if normalized_query.blank?

    escaped_query = ActiveRecord::Base.sanitize_sql_like(normalized_query)

    patient.recipes
      .includes(images: { file_attachment: :blob })
      .where(::Recipe.arel_table[:name].matches("#{escaped_query}%"))
      .order(:name, :id)
      .limit(MAX_RESULTS)
  end
end
