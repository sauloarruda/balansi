defmodule JournalWeb.Plugs.CORSPlug do
  @moduledoc """
  Custom CORS plug that reads origins from application config at runtime.
  Handles both preflight OPTIONS requests and actual requests.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    origin = get_req_header(conn, "origin") |> List.first()

    # Handle preflight OPTIONS requests
    if conn.method == "OPTIONS" do
      if origin && allowed_origin?(origin) do
        conn
        |> put_resp_header("access-control-allow-origin", origin)
        |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
        |> put_resp_header("access-control-allow-headers", "content-type, authorization")
        |> put_resp_header("access-control-allow-credentials", "false")
        |> put_resp_header("access-control-max-age", "86400")
        |> send_resp(200, "")
        |> halt()
      else
        conn
        |> send_resp(403, "")
        |> halt()
      end
    else
      # Add CORS headers to actual requests
      if origin && allowed_origin?(origin) do
        conn
        |> put_resp_header("access-control-allow-origin", origin)
        |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
        |> put_resp_header("access-control-allow-headers", "content-type, authorization")
        |> put_resp_header("access-control-allow-credentials", "false")
      else
        conn
      end
    end
  end

  defp allowed_origin?(origin) do
    cors_config = Application.get_env(:journal, :cors, [])
    allowed_origins = Keyword.get(cors_config, :origins, [])

    if Enum.empty?(allowed_origins) do
      # Fallback to localhost for development
      origin in ["http://localhost:5173", "http://localhost:8080", "http://localhost:3000"]
    else
      origin in allowed_origins
    end
  end
end
