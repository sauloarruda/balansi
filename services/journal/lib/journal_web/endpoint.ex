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
  # Uses custom plug that reads origins from runtime config
  plug JournalWeb.Plugs.CORSPlug

  plug Plug.Session, @session_options
  plug JournalWeb.Router
end
