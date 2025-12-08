import Config

# Configure your database
# Use DATABASE_URL if set, otherwise use individual config
if database_url = System.get_env("DATABASE_URL") do
  config :journal, Journal.Repo,
    url: database_url,
    stacktrace: true,
    show_sensitive_data_on_connection_error: true,
    pool_size: 10
else
  config :journal, Journal.Repo,
    username: System.get_env("DB_USER") || "balansi",
    password: System.get_env("DB_PASSWORD") || "password",
    hostname: System.get_env("DB_HOST") || "localhost",
    database: "journal_dev",
    stacktrace: true,
    show_sensitive_data_on_connection_error: true,
    pool_size: 10
end

# For development, we disable any cache and enable
# debugging and code reloading.
config :journal, JournalWeb.Endpoint,
  # Binding to loopback ipv4 address prevents access from other machines.
  # Change to `ip: {0, 0, 0, 0}` to allow access from other machines.
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "xZqhz7Hl0au7oV8KccKC6427JqXnvMZgCC+kj1/4h8Y1Hr0XzRiuzYZAScp5Eb0a",
  watchers: []

# Enable dev routes for dashboard and mailbox
config :journal, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :default_formatter, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime
