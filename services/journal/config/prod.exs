import Config

# Note: SSL is handled by API Gateway, not the application itself.
# If deploying outside Lambda, you may want to enable force_ssl.
# config :journal, JournalWeb.Endpoint, force_ssl: [rewrite_on: [:x_forwarded_proto]]

# Do not print debug messages in production
config :logger, level: :info

# Optimize for Lambda: reduce compile-time checks
config :phoenix, :plug_init_mode, :runtime

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
