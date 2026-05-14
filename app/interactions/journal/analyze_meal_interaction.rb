class Journal::AnalyzeMealInteraction < ActiveInteraction::Base
  DAILY_LIMIT = 50
  HOURLY_LIMIT = 10
  MAX_RETRIES = 3
  RECIPE_CONTEXT_FIELDS = %i[
    recipe_name
    portion_size_grams
    calories_per_portion
    proteins_per_portion
    carbs_per_portion
    fats_per_portion
  ].freeze

  include Journal::LlmRateLimitable

  object :meal, class: Meal
  integer :user_id
  string :description
  string :meal_type
  string :user_language, default: "pt"

  validates :description, presence: true, length: { maximum: 500 }
  validates :meal_type, inclusion: { in: Meal::MEAL_TYPES }
  validates :user_language, presence: true

  def execute
    return nil unless rate_limit_ok?

    analysis = call_llm_for_meal_analysis
    return nil unless analysis

    update_meal_with_analysis(analysis)
  end

  private

  def call_llm_for_meal_analysis
    retries = 0

    begin
      llm_client.analyze(**meal_analysis_attributes)
    rescue Journal::MealAnalysisClient::TransientError => e
      retries += 1
      if retries < MAX_RETRIES
        sleep((2**retries) * 0.1)
        retry
      end

      Rails.logger.error("Meal analysis transient failure user_id=#{user_id} meal_id=#{meal.id}: #{e.class}: #{e.message}")
      Sentry.capture_exception(e, tags: { meal_id: meal.id, user_id: user_id, reason: "transient_max_retries" })
      errors.add(:base, I18n.t("journal.errors.llm_unavailable", locale: user_language))
      nil
    rescue StandardError => e
      Rails.logger.error("Meal analysis failure user_id=#{user_id} meal_id=#{meal.id}: #{e.class}: #{e.message}")
      Sentry.capture_exception(e, tags: { meal_id: meal.id, user_id: user_id, reason: "unexpected_error" })
      errors.add(:base, I18n.t("journal.errors.llm_unavailable", locale: user_language))
      nil
    end
  end

  def llm_client
    @llm_client ||= Journal::MealAnalysisClient.new
  end

  def meal_analysis_attributes
    attributes = {
      description: description,
      meal_type: meal_type,
      user_language: user_language
    }
    context = recipe_context
    attributes[:recipe_context] = context if context.any?
    attributes
  end

  def recipe_context
    meal.meal_recipe_references.order(:id).pluck(*RECIPE_CONTEXT_FIELDS).map do |values|
      RECIPE_CONTEXT_FIELDS.zip(values).to_h
    end
  end

  def update_meal_with_analysis(raw_response)
    parsed_response = normalize_response(raw_response)
    return nil unless parsed_response

    meal.update!(
      proteins: parsed_response[:p],
      carbs: parsed_response[:c],
      fats: parsed_response[:f],
      calories: parsed_response[:cal],
      gram_weight: parsed_response[:gw],
      ai_comment: parsed_response[:cmt],
      feeling: parsed_response[:feel],
      status: :pending_patient
    )

    meal
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.record.errors.full_messages.to_sentence)
    nil
  end

  def normalize_response(raw_response)
    response = raw_response.respond_to?(:deep_symbolize_keys) ? raw_response.deep_symbolize_keys : {}
    missing_keys = %i[p c f cal gw cmt feel].reject { |key| response.key?(key) }
    return report_missing_keys(missing_keys) if missing_keys.any?

    normalized = cast_response(response)
    return normalized if valid_ranges?(normalized)

    report_invalid_values
    nil
  end

  def cast_response(response)
    {
      p: response[:p].to_i,
      c: response[:c].to_i,
      f: response[:f].to_i,
      cal: response[:cal].to_i,
      gw: response[:gw].to_i,
      cmt: response[:cmt].to_s.strip,
      feel: response[:feel].to_i
    }
  end

  def report_missing_keys(missing_keys)
    errors.add(:base, I18n.t("journal.errors.llm_unavailable", locale: user_language))
    Rails.logger.warn("Meal analysis invalid response: missing_keys=#{missing_keys.join(',')} meal_id=#{meal.id} user_id=#{user_id}")
    Sentry.capture_message("Meal analysis invalid LLM response", level: :error, tags: { meal_id: meal.id, user_id: user_id, missing_keys: missing_keys.join(",") })
    nil
  end

  def report_invalid_values
    errors.add(:base, I18n.t("journal.errors.llm_unavailable", locale: user_language))
    Sentry.capture_message("Meal analysis invalid LLM response values", level: :error, tags: { meal_id: meal.id, user_id: user_id })
  end

  def valid_ranges?(normalized)
    normalized[:p].between?(0, 10_000) &&
      normalized[:c].between?(0, 10_000) &&
      normalized[:f].between?(0, 10_000) &&
      normalized[:cal].between?(1, 49_999) &&
      normalized[:gw].between?(1, 99_999) &&
      [ Meal::FEELING_POSITIVE, Meal::FEELING_NEGATIVE ].include?(normalized[:feel]) &&
      normalized[:cmt].present?
  end

  def rate_limit_log_context
    {
      analysis_label: "Meal analysis",
      record_label: "meal_id",
      record_id: meal.id
    }
  end
end
