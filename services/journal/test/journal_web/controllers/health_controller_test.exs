defmodule JournalWeb.HealthControllerTest do
  @moduledoc """
  Tests for HealthController endpoints.

  Tests cover:
  - Health check response format and status codes
  - Database connectivity verification
  - Timestamp validation
  - Multiple route paths (/health and /journal/health)
  """
  use JournalWeb.ConnCase, async: true

  describe "GET /health" do
    test "returns 200 OK with health status", %{conn: conn} do
      conn = get(conn, ~p"/health")

      assert response(conn, 200)
      data = json_response(conn, 200)

      assert data["status"] == "ok"
      assert data["service"] == "journal"
      assert data["database"] == "connected"
      assert is_binary(data["timestamp"])
    end

    test "returns valid ISO8601 timestamp", %{conn: conn} do
      conn = get(conn, ~p"/health")
      data = json_response(conn, 200)

      assert {:ok, _datetime, _offset} = DateTime.from_iso8601(data["timestamp"])
    end

    test "health check works at root path", %{conn: conn} do
      conn = get(conn, "/health")
      assert response(conn, 200)

      data = json_response(conn, 200)
      assert data["status"] == "ok"
      assert data["database"] == "connected"
    end

    test "health check works at /journal/health path", %{conn: conn} do
      conn = get(conn, ~p"/journal/health")
      assert response(conn, 200)

      data = json_response(conn, 200)
      assert data["status"] == "ok"
      assert data["database"] == "connected"
    end

    test "includes all required fields in response", %{conn: conn} do
      conn = get(conn, ~p"/health")
      data = json_response(conn, 200)

      assert Map.has_key?(data, "status")
      assert Map.has_key?(data, "service")
      assert Map.has_key?(data, "database")
      assert Map.has_key?(data, "timestamp")
    end
  end
end
