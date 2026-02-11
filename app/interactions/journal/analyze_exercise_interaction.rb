class Journal::AnalyzeExerciseInteraction < ActiveInteraction::Base
  DAILY_LIMIT = 50
  HOURLY_LIMIT = 10
  MAX_RETRIES = 3

  include Journal::LlmRateLimitable

  object :exercise, class: Exercise
  integer :user_id
  string :description
  string :user_language, default: "pt"

  validates :description, presence: true, length: { maximum: 500 }
  validates :user_language, presence: true

  def execute
    return nil unless rate_limit_ok?

    analysis = call_llm_for_exercise_analysis
    return nil unless analysis

    update_exercise_with_analysis(analysis)
  end

  private

  def call_llm_for_exercise_analysis
    retries = 0

    begin
      llm_client.analyze(description: description, user_language: user_language)
    rescue Journal::ExerciseAnalysisClient::TransientError => e
      retries += 1
      if retries < MAX_RETRIES
        sleep((2**retries) * 0.1)
        retry
      end

      Rails.logger.error("Exercise analysis transient failure user_id=#{user_id} exercise_id=#{exercise.id}: #{e.class}: #{e.message}")
      errors.add(:base, I18n.t("journal.errors.exercise_llm_unavailable", locale: user_language))
      nil
    rescue StandardError => e
      Rails.logger.error("Exercise analysis failure user_id=#{user_id} exercise_id=#{exercise.id}: #{e.class}: #{e.message}")
      errors.add(:base, I18n.t("journal.errors.exercise_llm_unavailable", locale: user_language))
      nil
    end
  end

  def llm_client
    @llm_client ||= Journal::ExerciseAnalysisClient.new
  end

  def update_exercise_with_analysis(raw_response)
    parsed_response = normalize_response(raw_response)
    return nil unless parsed_response

    exercise.update!(
      duration: parsed_response[:d],
      calories: parsed_response[:cal],
      neat: parsed_response[:n],
      structured_description: parsed_response[:sd],
      status: :pending_patient
    )

    exercise
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.record.errors.full_messages.to_sentence)
    nil
  end

  def normalize_response(raw_response)
    response = raw_response.respond_to?(:deep_symbolize_keys) ? raw_response.deep_symbolize_keys : {}

    required_keys = %i[d cal n sd]
    missing_keys = required_keys.reject { |key| response.key?(key) }

    if missing_keys.any?
      errors.add(:base, I18n.t("journal.errors.exercise_llm_unavailable", locale: user_language))
      Rails.logger.warn("Exercise analysis invalid response: missing_keys=#{missing_keys.join(',')} exercise_id=#{exercise.id} user_id=#{user_id}")
      return nil
    end

    normalized = {
      d: response[:d].to_i,
      cal: response[:cal].to_i,
      n: response[:n].to_i,
      sd: response[:sd].to_s.strip
    }

    return normalized if valid_ranges?(normalized)

    errors.add(:base, I18n.t("journal.errors.exercise_llm_unavailable", locale: user_language))
    nil
  end

  def valid_ranges?(normalized)
    normalized[:d].between?(1, 1439) &&
      normalized[:cal].between?(0, 9_999) &&
      normalized[:n].between?(0, 4_999) &&
      normalized[:sd].present? &&
      normalized[:sd].length <= 255
  end

  def rate_limit_log_context
    {
      analysis_label: "Exercise analysis",
      record_label: "exercise_id",
      record_id: exercise.id
    }
  end
end
