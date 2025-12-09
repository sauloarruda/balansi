import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere.

# Enable server when PHX_SERVER=true (used for Lambda)
if System.get_env("PHX_SERVER") do
  config :journal, JournalWeb.Endpoint, server: true
end

# Port configuration (Lambda uses PORT env var)
# Skip in test environment to preserve test.exs port setting (4002)
if config_env() != :test do
  config :journal, JournalWeb.Endpoint,
    http: [port: String.to_integer(System.get_env("PORT") || "4000")]
end

# OpenAI configuration
if openai_key = System.get_env("OPENAI_API_KEY") do
  config :journal, :openai,
    api_key: openai_key,
    model: System.get_env("OPENAI_MODEL") || "gpt-4o-mini"
end

# CORS configuration from environment
if frontend_domain = System.get_env("FRONTEND_DOMAIN") do
  # Split by comma and trim whitespace
  origins = frontend_domain
    |> String.split(",")
    |> Enum.map(&String.trim/1)

  config :journal, :cors,
    origins: origins,
    allow_headers: ["content-type", "authorization"],
    allow_methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
end

# Cognito configuration
if cognito_domain = System.get_env("COGNITO_DOMAIN") do
  config :journal, :cognito,
    domain: cognito_domain,
    client_id: System.get_env("COGNITO_CLIENT_ID"),
    redirect_uri: System.get_env("COGNITO_REDIRECT_URI"),
    user_pool_id: System.get_env("COGNITO_USER_POOL_ID")
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :journal, Journal.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6,
    ssl: true,
    ssl_opts: [verify: :verify_none]

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :journal, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :journal, JournalWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: String.to_integer(System.get_env("PORT") || "4000")
    ],
    secret_key_base: secret_key_base
end
