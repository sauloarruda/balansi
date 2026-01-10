require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Require rack-attack for rate limiting
require "rack/attack"

# Require JWT gem for token verification
require "jwt"

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
      expire_after: 30.days  # Align with Cognito refresh_token_validity (30 days)

    # Configure i18n
    config.i18n.available_locales = [ :pt, :en ]
    config.i18n.default_locale = :pt

    # Add rack-attack middleware for rate limiting (disabled in test environment)
    # This should be early in the middleware stack
    config.middleware.use Rack::Attack unless Rails.env.test?
  end
end
