module Journal::LlmRateLimitable
  extend ActiveSupport::Concern

  private

  def rate_limit_ok?
    return true if rate_limit_disabled?

    day_key = daily_limit_key
    hour_key = hourly_limit_key

    if exceeded_limit?(day_key, self.class::DAILY_LIMIT)
      log_rate_limit_exceeded(limit: "daily", key: day_key)
      errors.add(:base, I18n.t("journal.errors.rate_limit_exceeded", locale: user_language))
      return false
    end

    if exceeded_limit?(hour_key, self.class::HOURLY_LIMIT)
      log_rate_limit_exceeded(limit: "hourly", key: hour_key)
      errors.add(:base, I18n.t("journal.errors.rate_limit_exceeded", locale: user_language))
      return false
    end

    increment_counter(day_key, expires_at: Time.current.end_of_day + 5.minutes)
    increment_counter(hour_key, expires_at: Time.current.end_of_hour + 5.minutes)
    true
  end

  def rate_limit_disabled?
    ActiveModel::Type::Boolean.new.cast(ENV["DISABLE_LLM_RATE_LIMIT"])
  end

  def exceeded_limit?(key, max)
    Rails.cache.read(key).to_i >= max
  end

  def increment_counter(key, expires_at:)
    current = Rails.cache.read(key).to_i
    Rails.cache.write(key, current + 1, expires_at: expires_at)
  end

  def daily_limit_key
    "journal:llm:user:#{user_id}:day:#{Time.current.strftime('%Y%m%d')}"
  end

  def hourly_limit_key
    "journal:llm:user:#{user_id}:hour:#{Time.current.strftime('%Y%m%d%H')}"
  end

  def log_rate_limit_exceeded(limit:, key:)
    context = rate_limit_log_context
    Rails.logger.warn(
      "#{context[:analysis_label]} rate limit exceeded limit=#{limit} key=#{key} user_id=#{user_id} " \
      "#{context[:record_label]}=#{context[:record_id]}"
    )
  end

  def rate_limit_log_context
    raise NotImplementedError, "#{self.class.name} must implement #rate_limit_log_context"
  end
end
