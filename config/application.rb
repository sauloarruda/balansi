require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Require rack-attack for rate limiting
require "rack/attack"

module Balansi
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Configure session store
    config.session_store :cookie_store,
      key: "_balansi_session",
      expire_after: 30.days

    # Configure i18n
    config.i18n.available_locales = [ :pt, :en ]
    config.i18n.default_locale = :pt

    # Add rack-attack middleware for rate limiting (disabled in test environment)
    # This should be early in the middleware stack
    config.middleware.use Rack::Attack unless Rails.env.test?

    # Use Rails routes to render custom error pages (403/404/500)
    config.exceptions_app = routes

    # Configures Action Mailer for any environment.
    # - Sender (from): reads credentials mailer_from, then ENV MAILER_FROM, then "support@<default_host>".
    # - SMTP delivery: reads credentials smtp: username/password; disabled when absent.
    # - Other SMTP params can be overridden via ENV vars (SMTP_ADDRESS, SMTP_PORT, etc.).
    def self.configure_smtp!(config, default_host: "localhost")
      from = Rails.application.credentials.mailer_from ||
             ENV.fetch("MAILER_FROM", "support@#{default_host}")
      config.action_mailer.default_options = { from: from }

      smtp_username = Rails.application.credentials.dig(:smtp, :username)
      smtp_password = Rails.application.credentials.dig(:smtp, :password)
      smtp_configured = smtp_username.present? && smtp_password.present?

      config.action_mailer.perform_deliveries = smtp_configured
      config.action_mailer.raise_delivery_errors = smtp_configured

      return unless smtp_configured

      config.action_mailer.delivery_method = :smtp
      config.action_mailer.smtp_settings = {
        user_name: smtp_username,
        password: smtp_password,
        address: ENV.fetch("SMTP_ADDRESS", "email-smtp.sa-east-1.amazonaws.com"),
        port: ENV.fetch("SMTP_PORT", 587).to_i,
        domain: ENV.fetch("SMTP_DOMAIN", default_host),
        authentication: ENV.fetch("SMTP_AUTHENTICATION", "plain").to_sym,
        enable_starttls_auto: ENV.fetch("SMTP_ENABLE_STARTTLS_AUTO", "true") == "true"
      }
    end
  end
end
