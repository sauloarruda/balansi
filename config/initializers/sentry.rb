# frozen_string_literal: true

Sentry.init do |config|
  config.breadcrumbs_logger = [ :active_support_logger, :http_logger ]
  config.dsn = ENV["SENTRY_DSN"]
  config.traces_sample_rate = ENV.fetch("SENTRY_TRACES_SAMPLE_RATE", 0.1).to_f

  # Only include PII (IPs, headers, cookies) in non-production environments.
  # This application handles health/nutrition data, so PII should be restricted in production.
  config.send_default_pii = !Rails.env.production?
end
