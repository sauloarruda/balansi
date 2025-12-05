defmodule JournalWeb.HealthController do
  use JournalWeb, :controller

  @doc """
  Health check endpoint for load balancers and monitoring.
  Returns 200 OK with service status.
  """
  def index(conn, _params) do
    conn
    |> put_status(:ok)
    |> json(%{
      status: "ok",
      service: "journal",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end
end

