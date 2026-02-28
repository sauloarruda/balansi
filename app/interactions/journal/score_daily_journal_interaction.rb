class Journal::ScoreDailyJournalInteraction < ActiveInteraction::Base
  DAILY_LIMIT = 50
  HOURLY_LIMIT = 10
  MAX_RETRIES = 3

  include Journal::LlmRateLimitable

  object :journal, class: Journal
  integer :user_id
  string :user_language, default: "pt"

  validates :journal, presence: true
  validates :user_language, presence: true

  def execute
    return nil unless rate_limit_ok?

    scoring = call_llm_for_scoring
    return nil unless scoring

    update_journal_with_score(scoring)
  end

  private

  def call_llm_for_scoring
    retries = 0

    begin
      llm_client.score(journal: journal, patient: journal.patient, user_language: user_language)
    rescue Journal::DailyScoringClient::TransientError => e
      retries += 1
      if retries < MAX_RETRIES
        sleep((2**retries) * 0.1)
        retry
      end

      Rails.logger.error("Daily scoring transient failure user_id=#{user_id} journal_id=#{journal.id}: #{e.class}: #{e.message}")
      errors.add(:base, I18n.t("journal.errors.scoring_unavailable", locale: user_language))
      nil
    rescue StandardError => e
      Rails.logger.error("Daily scoring failure user_id=#{user_id} journal_id=#{journal.id}: #{e.class}: #{e.message}")
      errors.add(:base, I18n.t("journal.errors.scoring_unavailable", locale: user_language))
      nil
    end
  end

  def llm_client
    @llm_client ||= Journal::DailyScoringClient.new
  end

  def update_journal_with_score(raw_response)
    parsed = normalize_response(raw_response)
    return nil unless parsed

    journal.update!(
      score: parsed[:s],
      feedback_positive: parsed[:fp],
      feedback_improvement: parsed[:fi]
    )

    journal
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.record.errors.full_messages.to_sentence)
    nil
  end

  def normalize_response(raw_response)
    response = raw_response.respond_to?(:deep_symbolize_keys) ? raw_response.deep_symbolize_keys : {}

    required_keys = %i[s fp fi]
    missing_keys = required_keys.reject { |key| response.key?(key) }

    if missing_keys.any?
      errors.add(:base, I18n.t("journal.errors.scoring_unavailable", locale: user_language))
      Rails.logger.warn("Daily scoring invalid response: missing_keys=#{missing_keys.join(',')} journal_id=#{journal.id} user_id=#{user_id}")
      return nil
    end

    normalized = {
      s: response[:s].to_i,
      fp: response[:fp].to_s.strip,
      fi: response[:fi].to_s.strip
    }

    return normalized if valid_ranges?(normalized)

    errors.add(:base, I18n.t("journal.errors.scoring_unavailable", locale: user_language))
    nil
  end

  def valid_ranges?(normalized)
    normalized[:s].between?(1, 5) &&
      normalized[:fp].present? &&
      normalized[:fi].present?
  end

  def rate_limit_log_context
    {
      analysis_label: "Daily scoring",
      record_label: "journal_id",
      record_id: journal.id
    }
  end
end
