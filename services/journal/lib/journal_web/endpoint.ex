defmodule JournalWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :journal

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_journal_key",
    signing_salt: "0r1a5jco",
    same_site: "Lax"
  ]

  # Serve at "/" the static files from "priv/static" directory.
  plug Plug.Static,
    at: "/",
    from: :journal,
    gzip: not code_reloading?,
    only: JournalWeb.static_paths(),
    raise_on_missing_only: code_reloading?

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :journal
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head

  # CORS configuration - must be before Router
  # Origins are read from application config at runtime for security
  plug Corsica,
    origins: &JournalWeb.Endpoint.allowed_origin?/1,
    allow_headers: ~w(content-type authorization),
    allow_methods: ~w(GET POST PUT PATCH DELETE OPTIONS),
    allow_credentials: false

  plug Plug.Session, @session_options
  plug JournalWeb.Router

  @doc """
  Checks if the given origin is allowed based on application configuration.

  Reads from `:journal, :cors, :origins` which can be set via:
  - `config/config.exs` for development defaults
  - `FRONTEND_DOMAIN` environment variable in production (via `runtime.exs`)
  """
  def allowed_origin?(origin) do
    cors_config = Application.get_env(:journal, :cors, [])
    allowed_origins = Keyword.get(cors_config, :origins, [])

    origin in allowed_origins
  end
end
