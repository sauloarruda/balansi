import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
# Use DATABASE_URL if set, otherwise use individual config
if database_url = System.get_env("DATABASE_URL") do
  config :journal, Journal.Repo,
    url: database_url,
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: System.schedulers_online() * 2
else
  config :journal, Journal.Repo,
    username: System.get_env("DB_USER") || "balansi",
    password: System.get_env("DB_PASSWORD") || "password",
    hostname: System.get_env("DB_HOST") || "localhost",
    database: "journal_test#{System.get_env("MIX_TEST_PARTITION")}",
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: System.schedulers_online() * 2
end

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :journal, JournalWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "15fcRovKBVM0qVDtLVbf2ONTcbqtX7xbSomonyuVMj5h2ggk/mKFsFclqX8u5Ujl",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
