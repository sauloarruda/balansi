defmodule JournalWeb.HealthController do
  @moduledoc """
  Health check controller for load balancer and monitoring integration.

  Provides endpoints for:
  - `/health` - Basic health check (used by Lambda Web Adapter)
  - `/journal/health` - Health check with API prefix

  Both endpoints return the same response format with service status,
  service name, database connectivity status, and timestamp.

  The health check verifies:
  - Service is running
  - Database (PostgreSQL) connectivity
  """
  use JournalWeb, :controller

  alias Journal.Repo

  @doc """
  Health check endpoint for load balancers and monitoring.
  Returns 200 OK with service status and database connectivity.
  Returns 503 Service Unavailable if database is unreachable.
  """
  def index(conn, _params) do
    timestamp = get_timestamp()

    case check_database_health() do
      :ok ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "ok",
          service: "journal",
          database: "connected",
          timestamp: timestamp
        })

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          status: "unhealthy",
          service: "journal",
          database: "disconnected",
          error: "Database health check failed: #{inspect(reason)}",
          timestamp: timestamp
        })
    end
  end

  # Private functions

  defp check_database_health do
    case Repo.query("SELECT 1", []) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp get_timestamp do
    try do
      DateTime.utc_now() |> DateTime.to_iso8601()
    rescue
      _ -> "unavailable"
    end
  end
end
