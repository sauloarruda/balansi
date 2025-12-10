defmodule Journal.Auth.CognitoClient do
  @moduledoc """
  Client for interacting with AWS Cognito OAuth2 endpoints.

  Provides functions to:
  - Exchange authorization code for tokens
  - Get user information from access token
  - Refresh access tokens using refresh tokens

  All functions use HTTP client (Req) to call Cognito OAuth2 endpoints.
  """

  require Logger

  @doc """
  Exchanges an authorization code for access and refresh tokens.

  ## Parameters
    - `code`: Authorization code received from Cognito redirect
    - `redirect_uri`: Redirect URI used in the authorization request (must match)

  ## Returns
    - `{:ok, tokens}` where tokens is a map with:
      - `access_token`: JWT access token
      - `refresh_token`: Refresh token for obtaining new access tokens
      - `expires_in`: Token expiration time in seconds
      - `token_type`: Token type (typically "Bearer")
    - `{:error, reason}` on failure

  ## Examples

      iex> CognitoClient.exchange_code_for_tokens("auth-code-123", "https://example.com/callback")
      {:ok, %{
        access_token: "eyJhbGc...",
        refresh_token: "refresh-token-123",
        expires_in: 3600,
        token_type: "Bearer"
      }}
  """
  def exchange_code_for_tokens(code, redirect_uri) do
    config = get_config()

    if config do
      token_url = build_token_url(config.domain)
      client_id = config.client_id

      body = [
        grant_type: "authorization_code",
        client_id: client_id,
        code: code,
        redirect_uri: redirect_uri
      ]

      opts = [form: body, receive_timeout: 30_000]

      Logger.info("Exchanging authorization code for tokens")

      case Req.post(token_url, opts) do
        {:ok, %Req.Response{status: 200, body: response_body}} ->
          tokens = %{
            access_token: response_body["access_token"],
            refresh_token: response_body["refresh_token"],
            expires_in: response_body["expires_in"],
            token_type: response_body["token_type"] || "Bearer"
          }

          Logger.info("Successfully exchanged code for tokens")
          {:ok, tokens}

        {:ok, %Req.Response{status: status, body: response_body}} ->
          Logger.error("Cognito token exchange failed with status #{status}: #{inspect(response_body)}")
          {:error, {:api_error, status, response_body}}

        {:error, reason} ->
          Logger.error("Cognito token exchange request failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      Logger.error("Cognito configuration not found")
      {:error, :configuration_not_found}
    end
  end

  @doc """
  Gets user information from Cognito using an access token.

  ## Parameters
    - `access_token`: JWT access token from Cognito

  ## Returns
    - `{:ok, user_info}` where user_info is a map with user attributes:
      - `sub`: User's Cognito sub (unique identifier)
      - `email`: User's email address
      - `name`: User's name (if available)
      - Other custom attributes as configured in Cognito
    - `{:error, reason}` on failure

  ## Examples

      iex> CognitoClient.get_user_info("eyJhbGc...")
      {:ok, %{
        sub: "cognito-user-123",
        email: "user@example.com",
        name: "John Doe"
      }}
  """
  def get_user_info(access_token) do
    config = get_config()

    if config do
      userinfo_url = build_userinfo_url(config.domain)

      headers = [
        {"authorization", "Bearer #{access_token}"}
      ]

      Logger.info("Fetching user info from Cognito")

      case Req.get(userinfo_url, headers: headers, receive_timeout: 30_000) do
        {:ok, %Req.Response{status: 200, body: response_body}} ->
          Logger.debug("Successfully fetched user info: #{inspect(response_body)}")
          {:ok, response_body}

        {:ok, %Req.Response{status: status, body: response_body}} ->
          Logger.error("Cognito userinfo request failed with status #{status}: #{inspect(response_body)}")
          {:error, {:api_error, status, response_body}}

        {:error, reason} ->
          Logger.error("Cognito userinfo request failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      Logger.error("Cognito configuration not found")
      {:error, :configuration_not_found}
    end
  end

  @doc """
  Refreshes an access token using a refresh token.

  ## Parameters
    - `refresh_token`: Refresh token obtained from initial token exchange

  ## Returns
    - `{:ok, tokens}` where tokens is a map with:
      - `access_token`: New JWT access token
      - `expires_in`: Token expiration time in seconds
      - `token_type`: Token type (typically "Bearer")
    - `{:error, reason}` on failure

  ## Examples

      iex> CognitoClient.refresh_access_token("refresh-token-123")
      {:ok, %{
        access_token: "eyJhbGc...",
        expires_in: 3600,
        token_type: "Bearer"
      }}
  """
  def refresh_access_token(refresh_token) do
    config = get_config()

    if config do
      token_url = build_token_url(config.domain)
      client_id = config.client_id

      body = [
        grant_type: "refresh_token",
        client_id: client_id,
        refresh_token: refresh_token
      ]

      opts = [form: body, receive_timeout: 30_000]

      Logger.info("Refreshing access token")

      case Req.post(token_url, opts) do
        {:ok, %Req.Response{status: 200, body: response_body}} ->
          tokens = %{
            access_token: response_body["access_token"],
            expires_in: response_body["expires_in"],
            token_type: response_body["token_type"] || "Bearer"
          }

          Logger.info("Successfully refreshed access token")
          {:ok, tokens}

        {:ok, %Req.Response{status: status, body: response_body}} ->
          Logger.error("Cognito token refresh failed with status #{status}: #{inspect(response_body)}")
          {:error, {:api_error, status, response_body}}

        {:error, reason} ->
          Logger.error("Cognito token refresh request failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      Logger.error("Cognito configuration not found")
      {:error, :configuration_not_found}
    end
  end

  # Private helper functions

  defp get_config do
    config = Application.get_env(:journal, :cognito)

    if config && config[:domain] && config[:client_id] do
      %{
        domain: config[:domain],
        client_id: config[:client_id],
        redirect_uri: config[:redirect_uri]
      }
    else
      nil
    end
  end

  defp build_token_url(domain) do
    # Ensure domain doesn't have trailing slash
    domain = String.trim_trailing(domain, "/")
    "#{domain}/oauth2/token"
  end

  defp build_userinfo_url(domain) do
    # Ensure domain doesn't have trailing slash
    domain = String.trim_trailing(domain, "/")
    "#{domain}/oauth2/userInfo"
  end
end
