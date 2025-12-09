defmodule JournalWeb.AuthController do
  @moduledoc """
  Controller for handling authentication flows with Cognito Hosted UI.

  Provides endpoints for:
  - `/auth/callback` - Handles OAuth2 callback from Cognito
  - `/auth/refresh` - Refreshes access token using refresh token from cookie

  The callback endpoint:
  1. Receives authorization code from Cognito redirect
  2. Exchanges code for tokens
  3. Gets user information from Cognito
  4. Creates or finds user in database
  5. Creates patient record
  6. Encrypts session data (refresh token + user ID) and sets in httpOnly cookie
  7. Redirects to frontend

  The refresh endpoint:
  1. Reads encrypted refresh token from session cookie
  2. Calls Cognito to refresh the access token
  3. Returns new access token with expiration time
  """

  use JournalWeb, :controller

  require Logger

  alias Journal.Auth
  alias Journal.Auth.CognitoClient
  alias Journal.Auth.Session
  alias JournalWeb.ErrorHandler

  @doc """
  Handles OAuth2 callback from Cognito Hosted UI.

  GET /auth/callback?code=...&state=...

  Flow:
  1. Extracts authorization code from query params
  2. Exchanges code for access and refresh tokens
  3. Gets user info from Cognito using access token
  4. Creates or finds user in database
  5. Creates patient record for user
  6. Encrypts session data (refresh token + user ID) and sets in httpOnly cookie
  7. Redirects to frontend URL

  Returns 400 Bad Request if code is missing.
  Returns 500 Internal Server Error if any step fails.
  """
  def callback(conn, params) do
    case params["code"] do
      nil ->
        Logger.error("Callback called without authorization code")
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Missing authorization code"})

      code ->
        handle_callback(conn, code, params["state"])
    end
  end

  @doc """
  Refreshes an access token using the refresh token from the session cookie.

  POST /auth/refresh

  Flow:
  1. Reads encrypted session data from httpOnly cookie
  2. Extracts refresh token from session
  3. Calls Cognito to refresh the access token
  4. Returns new access token with expiration time

  Returns 200 OK with JSON containing:
  - `access_token`: New JWT access token
  - `expires_in`: Token expiration time in seconds
  - `token_type`: Token type (typically "Bearer")

  Returns 401 Unauthorized if:
  - Session cookie is missing
  - Session data cannot be decrypted
  - Refresh token is invalid or expired

  Returns 500 Internal Server Error if Cognito API call fails.
  """
  def refresh(conn, _params) do
    case get_session_cookie(conn) do
      nil ->
        Logger.warning("Refresh endpoint called without session cookie")
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Missing session cookie"})

      encrypted_session ->
        handle_refresh(conn, encrypted_session)
    end
  end

  # Private functions

  defp handle_callback(conn, code, state) do
    config = get_cognito_config()

    if config do
      redirect_uri = config[:redirect_uri]

      with {:ok, tokens} <- CognitoClient.exchange_code_for_tokens(code, redirect_uri),
           {:ok, user_info} <- CognitoClient.get_user_info(tokens.access_token),
           {:ok, user} <- create_or_find_user(user_info),
           {:ok, _patient} <- create_patient(user.id),
           {:ok, encrypted_session} <- Session.encrypt_session(tokens.refresh_token, user.id),
           frontend_url <- get_frontend_url() do
        conn
        |> set_session_cookie(encrypted_session)
        |> redirect(external: build_redirect_url(frontend_url, state))
      else
        error ->
          Logger.error("Callback processing failed: #{inspect(error)}")
          ErrorHandler.handle_service_error(conn, error)
      end
    else
      Logger.error("Cognito configuration not found")
      conn
      |> put_status(:internal_server_error)
      |> json(%{error: "Authentication service not configured"})
    end
  end

  defp create_or_find_user(user_info) do
    cognito_id = user_info["sub"]
    attrs = %{
      name: user_info["name"] || user_info["email"] || "User",
      email: user_info["email"]
    }

    Auth.create_or_find_user(cognito_id, attrs)
  end

  defp create_patient(user_id) do
    professional_id = Auth.get_first_professional_id()
    Auth.create_patient(user_id, professional_id)
  end

  defp set_session_cookie(conn, encrypted_session) do
    # Cookie expires in 30 days (same as Cognito refresh token default)
    # httpOnly prevents JavaScript access
    # secure: true for HTTPS (will be set based on environment)
    # same_site: "Lax" for CSRF protection
    # The session data is encrypted, so even if someone views the cookie,
    # they cannot access the refresh token without the encryption secret
    cookie_opts = [
      http_only: true,
      max_age: 30 * 24 * 60 * 60, # 30 days in seconds
      same_site: "Lax",
      path: "/"
    ]

    # Add secure flag in production (HTTPS)
    cookie_opts = if is_production?(), do: Keyword.put(cookie_opts, :secure, true), else: cookie_opts

    # Use "session_id" name to match the Go auth service pattern
    put_resp_cookie(conn, "session_id", encrypted_session, cookie_opts)
  end

  defp get_cognito_config do
    config = Application.get_env(:journal, :cognito)

    if config && config[:domain] && config[:client_id] && config[:redirect_uri] do
      config
    else
      nil
    end
  end

  defp get_frontend_url do
    # Get frontend URL from environment or config
    # Priority: FRONTEND_URL env var > first origin from CORS config > default
    case System.get_env("FRONTEND_URL") do
      nil ->
        cors_config = Application.get_env(:journal, :cors, [])
        origins = Keyword.get(cors_config, :origins, [])

        case origins do
          [first_origin | _] -> first_origin
          [] -> "http://localhost:5173"
        end

      url ->
        url
    end
  end

  defp build_redirect_url(frontend_url, state) do
    # If state parameter exists, append it to the redirect URL
    # This allows the frontend to handle the state (e.g., redirect to specific page)
    case state do
      nil -> frontend_url
      state -> "#{frontend_url}?state=#{URI.encode(state)}"
    end
  end

  defp is_production? do
    Mix.env() == :prod
  end

  defp handle_refresh(conn, encrypted_session) do
    config = get_cognito_config()

    if config do
      with {:ok, session_data} <- Session.decrypt_session(encrypted_session),
           refresh_token <- session_data[:refresh_token],
           {:ok, tokens} <- CognitoClient.refresh_access_token(refresh_token) do
        conn
        |> put_status(:ok)
        |> json(%{
          access_token: tokens.access_token,
          expires_in: tokens.expires_in,
          token_type: tokens.token_type
        })
      else
        {:error, :decryption_failed} ->
          Logger.warning("Failed to decrypt session data during refresh")
          conn
          |> put_status(:unauthorized)
          |> json(%{error: "Invalid session"})

        {:error, :invalid_encoding} ->
          Logger.warning("Invalid session cookie encoding during refresh")
          conn
          |> put_status(:unauthorized)
          |> json(%{error: "Invalid session"})

        {:error, :configuration_not_found} ->
          Logger.error("Cognito configuration not found during refresh")
          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "Authentication service not configured"})

        {:error, {:api_error, status, body}} ->
          # Cognito returns 400 for invalid/expired refresh tokens
          if status == 400 do
            Logger.warning("Invalid or expired refresh token: #{inspect(body)}")
            conn
            |> put_status(:unauthorized)
            |> json(%{error: "Invalid or expired refresh token"})
          else
            Logger.error("Cognito refresh failed with status #{status}: #{inspect(body)}")
            ErrorHandler.handle_service_error(conn, {:error, {:api_error, status, body}})
          end

        error ->
          Logger.error("Unexpected error during token refresh: #{inspect(error)}")
          # Ensure error is in the correct format
          formatted_error = if match?({:error, _}, error), do: error, else: {:error, error}
          ErrorHandler.handle_service_error(conn, formatted_error)
      end
    else
      Logger.error("Cognito configuration not found")
      conn
      |> put_status(:internal_server_error)
      |> json(%{error: "Authentication service not configured"})
    end
  end

  defp get_session_cookie(conn) do
    # Get the session_id cookie value
    conn = Plug.Conn.fetch_cookies(conn)
    conn.req_cookies["session_id"]
  end
end
