class Recipes::AnalyzeNutritionInteraction < ActiveInteraction::Base
  DAILY_LIMIT = 50
  HOURLY_LIMIT = 10
  MAX_RETRIES = 3
  NUTRITION_ATTRIBUTES = %i[calories proteins carbs fats].freeze

  include Journal::LlmRateLimitable

  object :recipe, class: Recipe
  integer :user_id
  string :user_language, default: "pt"
  boolean :persist, default: true

  validates :user_language, presence: true

  def execute
    return recipe if nutrition_complete?
    return nil unless recipe_valid_for_analysis?
    return nil unless rate_limit_ok?

    analysis = call_llm_for_nutrition_analysis
    return nil unless analysis

    apply_analysis(analysis)
  end

  private

  def nutrition_complete?
    NUTRITION_ATTRIBUTES.all? { |attribute| recipe.public_send(attribute).present? }
  end

  def recipe_valid_for_analysis?
    return true if recipe.valid?

    recipe.errors.full_messages.each { |message| errors.add(:base, message) }
    false
  end

  def call_llm_for_nutrition_analysis
    retries = 0

    begin
      llm_client.analyze(
        name: recipe.name,
        ingredients: recipe.ingredients,
        instructions: recipe.instructions,
        portion_size_grams: recipe.portion_size_grams,
        user_language: user_language
      )
    rescue Recipes::NutritionAnalysisClient::TransientError => e
      retries += 1
      if retries < MAX_RETRIES
        sleep((2**retries) * 0.1)
        retry
      end

      report_exception(e, reason: "transient_max_retries")
      nil
    rescue StandardError => e
      report_exception(e, reason: "unexpected_error")
      nil
    end
  end

  def llm_client
    @llm_client ||= Recipes::NutritionAnalysisClient.new
  end

  def apply_analysis(raw_response)
    parsed_response = normalize_response(raw_response)
    return nil unless parsed_response

    recipe.assign_attributes(parsed_response)
    recipe.save! if persist
    recipe
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.record.errors.full_messages.to_sentence)
    nil
  end

  def normalize_response(raw_response)
    response = raw_response.respond_to?(:deep_symbolize_keys) ? raw_response.deep_symbolize_keys : {}
    missing_keys = NUTRITION_ATTRIBUTES.reject { |key| response.key?(key) }
    return report_missing_keys(missing_keys) if missing_keys.any?

    normalized = cast_response(response)
    return normalized if normalized && valid_ranges?(normalized)

    report_invalid_values
    nil
  end

  def cast_response(response)
    calories = numeric_value(response[:calories])
    proteins = numeric_value(response[:proteins])
    carbs = numeric_value(response[:carbs])
    fats = numeric_value(response[:fats])
    return nil if [ calories, proteins, carbs, fats ].any?(&:nil?)

    {
      calories: calories.round,
      proteins: proteins.round(2),
      carbs: carbs.round(2),
      fats: fats.round(2)
    }
  end

  def numeric_value(value)
    Float(value)
  rescue ArgumentError, TypeError
    nil
  end

  def valid_ranges?(normalized)
    normalized[:calories].between?(0, Recipe::CALORIES_MAX - 1) &&
      normalized[:proteins].between?(0, Recipe::MACROS_MAX - 1) &&
      normalized[:carbs].between?(0, Recipe::MACROS_MAX - 1) &&
      normalized[:fats].between?(0, Recipe::MACROS_MAX - 1)
  end

  def report_exception(exception, reason:)
    Rails.logger.error(
      "Recipe nutrition analysis failure user_id=#{user_id} recipe_id=#{recipe.id || 'new'}: " \
      "#{exception.class}: #{exception.message}"
    )
    Sentry.capture_exception(exception, tags: { recipe_id: recipe.id, user_id: user_id, reason: reason })
    errors.add(:base, I18n.t("patient.recipes.errors.nutrition_analysis_unavailable", locale: user_language))
  end

  def report_missing_keys(missing_keys)
    errors.add(:base, I18n.t("patient.recipes.errors.nutrition_analysis_unavailable", locale: user_language))
    Rails.logger.warn(
      "Recipe nutrition analysis invalid response: missing_keys=#{missing_keys.join(',')} " \
      "recipe_id=#{recipe.id || 'new'} user_id=#{user_id}"
    )
    Sentry.capture_message(
      "Recipe nutrition analysis invalid LLM response",
      level: :error,
      tags: { recipe_id: recipe.id, user_id: user_id, missing_keys: missing_keys.join(",") }
    )
    nil
  end

  def report_invalid_values
    errors.add(:base, I18n.t("patient.recipes.errors.nutrition_analysis_unavailable", locale: user_language))
    Sentry.capture_message(
      "Recipe nutrition analysis invalid LLM response values",
      level: :error,
      tags: { recipe_id: recipe.id, user_id: user_id }
    )
  end

  def rate_limit_log_context
    {
      analysis_label: "Recipe nutrition analysis",
      record_label: "recipe_id",
      record_id: recipe.id || "new"
    }
  end
end
