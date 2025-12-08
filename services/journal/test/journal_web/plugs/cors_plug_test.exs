defmodule JournalWeb.Plugs.CORSPlugTest do
  @moduledoc """
  Tests for CORSPlug.

  Tests cover:
  - Preflight OPTIONS requests with allowed origins
  - Preflight OPTIONS requests with disallowed origins
  - Preflight OPTIONS requests without origin header
  - Regular requests (GET, POST, etc.) with allowed origins
  - Regular requests with disallowed origins
  - Regular requests without origin header
  - Fallback to localhost when no CORS config is set
  - Custom CORS configuration from application config
  """
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias JournalWeb.Plugs.CORSPlug

  describe "preflight OPTIONS requests" do
    test "allows preflight request with allowed origin (localhost fallback)" do
      conn =
        :options
        |> conn("/api/test")
        |> put_req_header("origin", "http://localhost:5173")
        |> put_req_header("access-control-request-method", "POST")
        |> CORSPlug.call([])

      assert conn.status == 200
      assert get_resp_header(conn, "access-control-allow-origin") == ["http://localhost:5173"]
      assert get_resp_header(conn, "access-control-allow-methods") == ["GET, POST, PUT, PATCH, DELETE, OPTIONS"]
      assert get_resp_header(conn, "access-control-allow-headers") == ["content-type, authorization"]
      assert get_resp_header(conn, "access-control-allow-credentials") == ["false"]
      assert get_resp_header(conn, "access-control-max-age") == ["86400"]
      assert conn.halted
    end

    test "allows preflight request with another localhost port" do
      conn =
        :options
        |> conn("/api/test")
        |> put_req_header("origin", "http://localhost:8080")
        |> CORSPlug.call([])

      assert conn.status == 200
      assert get_resp_header(conn, "access-control-allow-origin") == ["http://localhost:8080"]
      assert conn.halted
    end

    test "rejects preflight request with disallowed origin" do
      conn =
        :options
        |> conn("/api/test")
        |> put_req_header("origin", "http://evil.com")
        |> CORSPlug.call([])

      assert conn.status == 403
      assert conn.halted
    end

    test "rejects preflight request without origin header" do
      conn =
        :options
        |> conn("/api/test")
        |> CORSPlug.call([])

      assert conn.status == 403
      assert conn.halted
    end

    test "allows preflight request with custom configured origin" do
      # Set custom CORS config
      Application.put_env(:journal, :cors, origins: ["https://app.balansi.me"])

      conn =
        :options
        |> conn("/api/test")
        |> put_req_header("origin", "https://app.balansi.me")
        |> CORSPlug.call([])

      assert conn.status == 200
      assert get_resp_header(conn, "access-control-allow-origin") == ["https://app.balansi.me"]
      assert conn.halted

      # Clean up
      Application.delete_env(:journal, :cors)
    end

    test "rejects preflight request with origin not in custom config" do
      # Set custom CORS config
      Application.put_env(:journal, :cors, origins: ["https://app.balansi.me"])

      conn =
        :options
        |> conn("/api/test")
        |> put_req_header("origin", "http://localhost:5173")
        |> CORSPlug.call([])

      assert conn.status == 403
      assert conn.halted

      # Clean up
      Application.delete_env(:journal, :cors)
    end
  end

  describe "regular requests (non-OPTIONS)" do
    test "adds CORS headers to GET request with allowed origin" do
      conn =
        :get
        |> conn("/api/test")
        |> put_req_header("origin", "http://localhost:5173")
        |> CORSPlug.call([])

      # Status is nil when not sent yet (will be set by router)
      assert is_nil(conn.status)
      assert get_resp_header(conn, "access-control-allow-origin") == ["http://localhost:5173"]
      assert get_resp_header(conn, "access-control-allow-methods") == ["GET, POST, PUT, PATCH, DELETE, OPTIONS"]
      assert get_resp_header(conn, "access-control-allow-headers") == ["content-type, authorization"]
      assert get_resp_header(conn, "access-control-allow-credentials") == ["false"]
      refute conn.halted
    end

    test "adds CORS headers to POST request with allowed origin" do
      conn =
        :post
        |> conn("/api/test", %{})
        |> put_req_header("origin", "http://localhost:8080")
        |> CORSPlug.call([])

      assert get_resp_header(conn, "access-control-allow-origin") == ["http://localhost:8080"]
      refute conn.halted
    end

    test "does not add CORS headers to request with disallowed origin" do
      conn =
        :get
        |> conn("/api/test")
        |> put_req_header("origin", "http://evil.com")
        |> CORSPlug.call([])

      assert get_resp_header(conn, "access-control-allow-origin") == []
      refute conn.halted
    end

    test "does not add CORS headers to request without origin header" do
      conn =
        :get
        |> conn("/api/test")
        |> CORSPlug.call([])

      assert get_resp_header(conn, "access-control-allow-origin") == []
      refute conn.halted
    end

    test "adds CORS headers to request with custom configured origin" do
      # Set custom CORS config
      Application.put_env(:journal, :cors, origins: ["https://app.balansi.me"])

      conn =
        :get
        |> conn("/api/test")
        |> put_req_header("origin", "https://app.balansi.me")
        |> CORSPlug.call([])

      assert get_resp_header(conn, "access-control-allow-origin") == ["https://app.balansi.me"]
      refute conn.halted

      # Clean up
      Application.delete_env(:journal, :cors)
    end

    test "does not add CORS headers when origin not in custom config" do
      # Set custom CORS config
      Application.put_env(:journal, :cors, origins: ["https://app.balansi.me"])

      conn =
        :get
        |> conn("/api/test")
        |> put_req_header("origin", "http://localhost:5173")
        |> CORSPlug.call([])

      assert get_resp_header(conn, "access-control-allow-origin") == []
      refute conn.halted

      # Clean up
      Application.delete_env(:journal, :cors)
    end
  end

  describe "init/1" do
    test "returns opts unchanged" do
      opts = [some: :option]
      assert CORSPlug.init(opts) == opts
    end
  end
end
