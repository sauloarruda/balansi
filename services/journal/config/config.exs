# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :journal,
  ecto_repos: [Journal.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :journal, JournalWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: JournalWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Journal.PubSub

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# OpenAI configuration (will be set via runtime.exs)
config :journal, :openai,
  api_key: nil,
  model: "gpt-4.1-mini"

# CORS configuration
config :journal, :cors,
  origins: ["http://localhost:5173", "http://localhost:8080", "http://localhost:3000"],
  allow_headers: ["content-type", "authorization"],
  allow_methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
