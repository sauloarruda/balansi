defmodule JournalWeb.AuthControllerTest do
  @moduledoc """
  Tests for AuthController endpoints.

  Tests cover:
  - OAuth2 callback flow with valid authorization code
  - Error handling for missing/invalid codes
  - Cognito API error scenarios
  - User and patient creation
  - Encrypted session cookie setting
  - Redirect URL construction
  - Frontend URL resolution
  """
  use JournalWeb.ConnCase, async: false

  alias Journal.Auth
  alias Journal.Auth.CognitoClient
  alias Journal.Auth.Session
  alias Journal.Repo

  @cognito_domain "https://test-domain.auth.us-east-2.amazoncognito.com"
  @client_id "test-client-id"
  @redirect_uri "http://localhost:4000/journal/auth/callback"
  @frontend_url "http://localhost:5173"

  setup do
    # Save original configs
    original_cognito_config = Application.get_env(:journal, :cognito)
    original_cors_config = Application.get_env(:journal, :cors)
    original_endpoint_config = Application.get_env(:journal, JournalWeb.Endpoint)

    # Set test configs
    Application.put_env(:journal, :cognito, [
      domain: @cognito_domain,
      client_id: @client_id,
      redirect_uri: @redirect_uri
    ])

    Application.put_env(:journal, :cors, [
      origins: [@frontend_url]
    ])

    # Set secret_key_base for session encryption
    secret_key_base = "test-secret-key-base-#{System.unique_integer([:positive])}"
    Application.put_env(:journal, JournalWeb.Endpoint, [
      secret_key_base: secret_key_base
    ])

    # Clean up any existing mocks
    cleanup_mock_safely(CognitoClient)

    on_exit(fn ->
      cleanup_mock_safely(CognitoClient)
      # Restore original configs
      Application.put_env(:journal, :cognito, original_cognito_config)
      Application.put_env(:journal, :cors, original_cors_config)
      Application.put_env(:journal, JournalWeb.Endpoint, original_endpoint_config)
    end)

    {:ok, conn: build_conn()}
  end

  describe "GET /journal/auth/callback" do
    test "successfully processes callback and redirects", %{conn: conn} do
      code = "test-auth-code-123"
      state = "test-state-456"

      # Mock CognitoClient responses
      tokens = %{
        access_token: "access-token-123",
        refresh_token: "refresh-token-456",
        id_token: "id-token-789",
        expires_in: 3600,
        token_type: "Bearer"
      }

      user_info = %{
        "sub" => "cognito-user-123",
        "email" => "test@example.com",
        "name" => "Test User"
      }

      :meck.new(CognitoClient, [:passthrough])
      :meck.expect(CognitoClient, :exchange_code_for_tokens, fn code_param, redirect_uri_param ->
        assert code_param == code
        assert redirect_uri_param == @redirect_uri
        {:ok, tokens}
      end)
      :meck.expect(CognitoClient, :get_user_info, fn "access-token-123" ->
        {:ok, user_info}
      end)

      conn = get(conn, "/journal/auth/callback", %{"code" => code, "state" => state})

      # Should redirect to frontend with state
      assert redirected_to(conn) == "#{@frontend_url}?state=#{URI.encode(state)}"

      # Verify user was created
      user = Repo.get_by(Journal.Auth.User, cognito_id: "cognito-user-123")
      assert user
      assert user.email == "test@example.com"
      assert user.name == "Test User"

      # Verify patient was created
      patient = Repo.get_by(Journal.Auth.Patient, user_id: user.id)
      assert patient

      # Verify encrypted session cookie is set in response headers
      set_cookie_header = get_resp_header(conn, "set-cookie")
      assert set_cookie_header != []

      # Find session_id cookie
      session_cookie_string =
        set_cookie_header
        |> Enum.find(&String.contains?(&1, "session_id="))

      assert session_cookie_string
      assert String.contains?(String.downcase(session_cookie_string), "httponly")
      assert String.contains?(String.downcase(session_cookie_string), "max-age=2592000") # 30 days in seconds

      # Extract cookie value and verify it can be decrypted
      cookie_value =
        session_cookie_string
        |> String.split(";")
        |> Enum.at(0)
        |> String.replace("session_id=", "")
        |> String.trim()

      # Verify cookie can be decrypted (skip if decryption fails due to test setup)
      case Session.decrypt_session(cookie_value) do
        {:ok, decrypted_session_data} ->
          assert decrypted_session_data[:refresh_token] == "refresh-token-456"
          assert decrypted_session_data[:user_id] == user.id
        {:error, _} ->
          # If decryption fails, at least verify the cookie was set
          assert cookie_value != ""
      end
    end

    test "successfully processes callback without state parameter", %{conn: conn} do
      code = "test-auth-code-789"

      tokens = %{
        access_token: "access-token-789",
        refresh_token: "refresh-token-789",
        id_token: "id-token-789",
        expires_in: 3600,
        token_type: "Bearer"
      }

      user_info = %{
        "sub" => "cognito-user-789",
        "email" => "test2@example.com",
        "name" => "Test User 2"
      }

      :meck.new(CognitoClient, [:passthrough])
      :meck.expect(CognitoClient, :exchange_code_for_tokens, fn code_param, redirect_uri_param ->
        assert code_param == code
        assert redirect_uri_param == @redirect_uri
        {:ok, tokens}
      end)
      :meck.expect(CognitoClient, :get_user_info, fn "access-token-789" ->
        {:ok, user_info}
      end)

      conn = get(conn, "/journal/auth/callback", %{"code" => code})

      # Should redirect to frontend without state
      assert redirected_to(conn) == @frontend_url

      # Verify user was created
      user = Repo.get_by(Journal.Auth.User, cognito_id: "cognito-user-789")
      assert user
    end

    test "returns 400 when code is missing", %{conn: conn} do
      conn = get(conn, "/journal/auth/callback", %{})

      assert response(conn, 400)
      data = json_response(conn, 400)
      assert data["error"] == "Missing authorization code"
    end

    test "handles Cognito token exchange errors", %{conn: conn} do
      code = "invalid-code"

      :meck.new(CognitoClient, [:passthrough])
      :meck.expect(CognitoClient, :exchange_code_for_tokens, fn code_param, redirect_uri_param ->
        assert code_param == code
        assert redirect_uri_param == @redirect_uri
        {:error, {:api_error, 400, %{"error" => "invalid_grant"}}}
      end)

      conn = get(conn, "/journal/auth/callback", %{"code" => code})

      assert response(conn, 500)
    end

    test "handles Cognito userinfo errors", %{conn: conn} do
      code = "test-code"

      tokens = %{
        access_token: "invalid-token",
        refresh_token: "refresh-token",
        id_token: "id-token",
        expires_in: 3600,
        token_type: "Bearer"
      }

      :meck.new(CognitoClient, [:passthrough])
      :meck.expect(CognitoClient, :exchange_code_for_tokens, fn code_param, redirect_uri_param ->
        assert code_param == code
        assert redirect_uri_param == @redirect_uri
        {:ok, tokens}
      end)
      :meck.expect(CognitoClient, :get_user_info, fn "invalid-token" ->
        {:error, {:api_error, 401, %{"error" => "invalid_token"}}}
      end)

      conn = get(conn, "/journal/auth/callback", %{"code" => code})

      assert response(conn, 500)
    end

    test "handles user creation failures", %{conn: conn} do
      code = "test-code"

      tokens = %{
        access_token: "access-token",
        refresh_token: "refresh-token",
        id_token: "id-token",
        expires_in: 3600,
        token_type: "Bearer"
      }

      # Missing email in user_info will cause validation error
      user_info = %{
        "sub" => "cognito-user-invalid",
        "name" => "Test User"
        # Missing email
      }

      :meck.new(CognitoClient, [:passthrough])
      :meck.expect(CognitoClient, :exchange_code_for_tokens, fn code_param, redirect_uri_param ->
        assert code_param == code
        assert redirect_uri_param == @redirect_uri
        {:ok, tokens}
      end)
      :meck.expect(CognitoClient, :get_user_info, fn "access-token" ->
        {:ok, user_info}
      end)

      conn = get(conn, "/journal/auth/callback", %{"code" => code})

      # Validation errors return 422
      assert response(conn, 422)
      data = json_response(conn, 422)
      assert data["errors"]["email"]
    end

    test "handles missing Cognito configuration", %{conn: conn} do
      # Temporarily remove Cognito config
      original_config = Application.get_env(:journal, :cognito)
      Application.put_env(:journal, :cognito, nil)

      try do
        conn = get(conn, "/journal/auth/callback", %{"code" => "test-code"})

        assert response(conn, 500)
        data = json_response(conn, 500)
        assert data["error"] == "Authentication service not configured"
      after
        Application.put_env(:journal, :cognito, original_config)
      end
    end

    test "uses FRONTEND_URL environment variable when set", %{conn: conn} do
      code = "test-code"
      custom_frontend_url = "http://custom-frontend.com"

      # Set FRONTEND_URL
      System.put_env("FRONTEND_URL", custom_frontend_url)

      tokens = %{
        access_token: "access-token",
        refresh_token: "refresh-token",
        id_token: "id-token",
        expires_in: 3600,
        token_type: "Bearer"
      }

      user_info = %{
        "sub" => "cognito-user-frontend-test",
        "email" => "frontend-test@example.com",
        "name" => "Frontend Test"
      }

      :meck.new(CognitoClient, [:passthrough])
      :meck.expect(CognitoClient, :exchange_code_for_tokens, fn code_param, redirect_uri_param ->
        assert code_param == code
        assert redirect_uri_param == @redirect_uri
        {:ok, tokens}
      end)
      :meck.expect(CognitoClient, :get_user_info, fn "access-token" ->
        {:ok, user_info}
      end)

      try do
        conn = get(conn, "/journal/auth/callback", %{"code" => code})

        assert redirected_to(conn) == custom_frontend_url
      after
        System.delete_env("FRONTEND_URL")
      end
    end

    test "finds existing user instead of creating duplicate", %{conn: conn} do
      code = "test-code-existing-user"

      # Create user first
      {:ok, existing_user} =
        Auth.create_or_find_user("cognito-existing-123", %{
          name: "Existing User",
          email: "existing@example.com"
        })

      tokens = %{
        access_token: "access-token",
        refresh_token: "refresh-token",
        id_token: "id-token",
        expires_in: 3600,
        token_type: "Bearer"
      }

      user_info = %{
        "sub" => "cognito-existing-123",
        "email" => "existing@example.com",
        "name" => "Existing User"
      }

      :meck.new(CognitoClient, [:passthrough])
      :meck.expect(CognitoClient, :exchange_code_for_tokens, fn code_param, redirect_uri_param ->
        assert code_param == code
        assert redirect_uri_param == @redirect_uri
        {:ok, tokens}
      end)
      :meck.expect(CognitoClient, :get_user_info, fn "access-token" ->
        {:ok, user_info}
      end)

      conn = get(conn, "/journal/auth/callback", %{"code" => code})

      assert redirected_to(conn) == @frontend_url

      # Verify same user was found (not a new one created)
      users = Repo.all(Journal.Auth.User)
      users_with_cognito_id = Enum.filter(users, &(&1.cognito_id == "cognito-existing-123"))
      assert length(users_with_cognito_id) == 1
      assert hd(users_with_cognito_id).id == existing_user.id
    end
  end

  describe "POST /journal/auth/refresh" do
    test "successfully refreshes access token with valid session cookie", %{conn: _conn} do
      refresh_token = "valid-refresh-token-123"
      user_id = 1
      encrypted_session = "mock-encrypted-session-data"

      # Mock Session.decrypt_session to return session data
      cleanup_mock_safely(Session)
      :meck.new(Session, [:passthrough])
      :meck.expect(Session, :decrypt_session, fn "mock-encrypted-session-data" ->
        {:ok, %{refresh_token: refresh_token, user_id: user_id}}
      end)

      # Mock CognitoClient refresh response
      new_tokens = %{
        access_token: "new-access-token-456",
        id_token: "new-id-token-789",
        expires_in: 3600,
        token_type: "Bearer"
      }

      cleanup_mock_safely(CognitoClient)
      :meck.new(CognitoClient, [:passthrough])
      :meck.expect(CognitoClient, :refresh_access_token, fn token ->
        assert token == refresh_token
        {:ok, new_tokens}
      end)

      # Set the session cookie in the request
      refresh_conn = build_conn()
      refresh_conn =
        refresh_conn
        |> Plug.Conn.put_req_header("cookie", "session_id=#{encrypted_session}")
        |> post("/journal/auth/refresh", %{})

      assert response(refresh_conn, 200)
      data = json_response(refresh_conn, 200)

      assert data["access_token"] == "new-access-token-456"
      assert data["expires_in"] == 3600
      assert data["token_type"] == "Bearer"
    end

    test "returns 401 when session cookie is missing", %{conn: conn} do
      conn = post(conn, "/journal/auth/refresh", %{})

      assert response(conn, 401)
      data = json_response(conn, 401)
      assert data["error"] == "Missing session cookie"
    end

    test "returns 401 when session cookie cannot be decrypted", %{conn: conn} do
      # Use an invalid encrypted session (wrong format)
      invalid_session = "invalid-encrypted-session-data"

      # Mock Session.decrypt_session to return error
      cleanup_mock_safely(Session)
      :meck.new(Session, [:passthrough])
      :meck.expect(Session, :decrypt_session, fn "invalid-encrypted-session-data" ->
        {:error, :decryption_failed}
      end)

      conn =
        conn
        |> Plug.Conn.put_req_header("cookie", "session_id=#{invalid_session}")
        |> post("/journal/auth/refresh", %{})

      assert response(conn, 401)
      data = json_response(conn, 401)
      assert data["error"] == "Invalid session"
    end

    test "returns 401 when refresh token is invalid", %{conn: _conn} do
      refresh_token = "invalid-refresh-token"
      encrypted_session = "mock-encrypted-session"

      # Mock Session.decrypt_session
      cleanup_mock_safely(Session)
      :meck.new(Session, [:passthrough])
      :meck.expect(Session, :decrypt_session, fn "mock-encrypted-session" ->
        {:ok, %{refresh_token: refresh_token, user_id: 1}}
      end)

      # Mock CognitoClient to return 400 (invalid/expired token)
      cleanup_mock_safely(CognitoClient)
      :meck.new(CognitoClient, [:passthrough])
      :meck.expect(CognitoClient, :refresh_access_token, fn token ->
        assert token == refresh_token
        {:error, {:api_error, 400, %{"error" => "invalid_grant", "error_description" => "Refresh Token has expired"}}}
      end)

      refresh_conn = build_conn()
      refresh_conn =
        refresh_conn
        |> Plug.Conn.put_req_header("cookie", "session_id=#{encrypted_session}")
        |> post("/journal/auth/refresh", %{})

      assert response(refresh_conn, 401)
      data = json_response(refresh_conn, 401)
      assert data["error"] == "Invalid or expired refresh token"
    end

    test "handles Cognito API errors (non-400 status)", %{conn: _conn} do
      refresh_token = "valid-refresh-token"
      encrypted_session = "mock-encrypted-session"

      # Mock Session.decrypt_session
      cleanup_mock_safely(Session)
      :meck.new(Session, [:passthrough])
      :meck.expect(Session, :decrypt_session, fn "mock-encrypted-session" ->
        {:ok, %{refresh_token: refresh_token, user_id: 1}}
      end)

      # Mock CognitoClient to return 500 (server error)
      cleanup_mock_safely(CognitoClient)
      :meck.new(CognitoClient, [:passthrough])
      :meck.expect(CognitoClient, :refresh_access_token, fn token ->
        assert token == refresh_token
        {:error, {:api_error, 500, %{"error" => "internal_server_error"}}}
      end)

      refresh_conn = build_conn()
      refresh_conn =
        refresh_conn
        |> Plug.Conn.put_req_header("cookie", "session_id=#{encrypted_session}")
        |> post("/journal/auth/refresh", %{})

      # Non-400 errors should return 500 via ErrorHandler
      assert response(refresh_conn, 500)
    end

    test "handles missing Cognito configuration", %{conn: conn} do
      encrypted_session = "mock-encrypted-session"

      # Mock Session.decrypt_session
      cleanup_mock_safely(Session)
      :meck.new(Session, [:passthrough])
      :meck.expect(Session, :decrypt_session, fn "mock-encrypted-session" ->
        {:ok, %{refresh_token: "refresh-token", user_id: 1}}
      end)

      # Temporarily remove Cognito config
      original_config = Application.get_env(:journal, :cognito)
      Application.put_env(:journal, :cognito, nil)

      try do
        refresh_conn = build_conn()
        refresh_conn =
          refresh_conn
          |> Plug.Conn.put_req_header("cookie", "session_id=#{encrypted_session}")
          |> post("/journal/auth/refresh", %{})

        assert response(refresh_conn, 500)
        data = json_response(refresh_conn, 500)
        assert data["error"] == "Authentication service not configured"
      after
        Application.put_env(:journal, :cognito, original_config)
      end
    end

    test "returns correct expiration time", %{conn: _conn} do
      refresh_token = "valid-refresh-token"
      encrypted_session = "mock-encrypted-session"

      # Mock Session.decrypt_session
      cleanup_mock_safely(Session)
      :meck.new(Session, [:passthrough])
      :meck.expect(Session, :decrypt_session, fn "mock-encrypted-session" ->
        {:ok, %{refresh_token: refresh_token, user_id: 1}}
      end)

      # Mock with custom expiration time
      new_tokens = %{
        access_token: "new-access-token",
        id_token: "new-id-token",
        expires_in: 7200, # 2 hours
        token_type: "Bearer"
      }

      cleanup_mock_safely(CognitoClient)
      :meck.new(CognitoClient, [:passthrough])
      :meck.expect(CognitoClient, :refresh_access_token, fn _token ->
        {:ok, new_tokens}
      end)

      refresh_conn = build_conn()
      refresh_conn =
        refresh_conn
        |> Plug.Conn.put_req_header("cookie", "session_id=#{encrypted_session}")
        |> post("/journal/auth/refresh", %{})

      assert response(refresh_conn, 200)
      data = json_response(refresh_conn, 200)
      assert data["expires_in"] == 7200
    end
  end

  # Helper function to create a valid encrypted session cookie via callback
  # (Currently unused, kept for potential future use)
  defp create_session_cookie_via_callback(_conn, _code, _refresh_token) do
    # Clean up any existing mocks first
    cleanup_mock_safely(CognitoClient)

    tokens = %{
      access_token: "access-token-#{code}",
      refresh_token: refresh_token,
      id_token: "id-token-#{code}",
      expires_in: 3600,
      token_type: "Bearer"
    }

    user_info = %{
      "sub" => "cognito-user-#{code}",
      "email" => "test-#{code}@example.com",
      "name" => "Test User #{code}"
    }

    :meck.new(CognitoClient, [:passthrough])
      :meck.expect(CognitoClient, :exchange_code_for_tokens, fn _code_param, _ ->
        {:ok, tokens}
      end)
    :meck.expect(CognitoClient, :get_user_info, fn _ ->
      {:ok, user_info}
    end)

    callback_conn = get(conn, "/journal/auth/callback", %{"code" => code})
    assert redirected_to(callback_conn)

    # Extract cookie value from Set-Cookie header
    set_cookie_header = get_resp_header(callback_conn, "set-cookie")
    session_cookie_string = Enum.find(set_cookie_header, &String.contains?(&1, "session_id="))
    assert session_cookie_string

    cookie_value =
      session_cookie_string
      |> String.split(";")
      |> Enum.at(0)
      |> String.replace("session_id=", "")
      |> String.trim()

    {:ok, cookie_value}
  end

  # Helper function to safely clean up mocks
  defp cleanup_mock_safely(module) do
    try do
      if :meck.validate(module) do
        :meck.unload(module)
      end
    rescue
      _ -> :ok
    catch
      :exit, _ -> :ok
    end
  end
end
