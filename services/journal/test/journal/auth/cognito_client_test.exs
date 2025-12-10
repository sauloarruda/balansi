defmodule Journal.Auth.CognitoClientTest do
  @moduledoc """
  Tests for CognitoClient module.

  Tests cover:
  - Exchanging authorization code for tokens
  - Getting user info from access token
  - Refreshing access tokens
  - Error handling for various failure scenarios
  - Configuration validation
  """
  use ExUnit.Case, async: false

  alias Journal.Auth.CognitoClient

  @cognito_domain "https://test-domain.auth.us-east-2.amazoncognito.com"
  @client_id "test-client-id"
  @redirect_uri "https://example.com/callback"

  setup do
    # Save original config
    original_config = Application.get_env(:journal, :cognito)

    # Set test config
    Application.put_env(:journal, :cognito, [
      domain: @cognito_domain,
      client_id: @client_id,
      redirect_uri: @redirect_uri
    ])

    # Clean up any existing mocks
    cleanup_mock_safely()

    on_exit(fn ->
      cleanup_mock_safely()
      # Restore original config
      Application.put_env(:journal, :cognito, original_config)
    end)

    :ok
  end

  describe "exchange_code_for_tokens/2" do
    test "successfully exchanges code for tokens" do
      code = "test-auth-code-123"
      redirect_uri = @redirect_uri

      expected_response = %{
        "access_token" => "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
        "refresh_token" => "refresh-token-123",
        "id_token" => "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
        "expires_in" => 3600,
        "token_type" => "Bearer"
      }

      token_url = "#{@cognito_domain}/oauth2/token"

      create_mock(fn ->
        :meck.expect(Req, :post, fn url, opts ->
          if url == token_url do
            {:ok, %Req.Response{status: 200, body: expected_response}}
          else
            :meck.passthrough([Req, :post, url, opts])
          end
        end)
      end)

      assert {:ok, tokens} = CognitoClient.exchange_code_for_tokens(code, redirect_uri)

      assert tokens.access_token == expected_response["access_token"]
      assert tokens.refresh_token == expected_response["refresh_token"]
      assert tokens.expires_in == expected_response["expires_in"]
      assert tokens.token_type == expected_response["token_type"]
    end

    test "handles API error response" do
      code = "invalid-code"
      redirect_uri = @redirect_uri

      error_response = %{
        "error" => "invalid_grant",
        "error_description" => "Invalid authorization code"
      }

      token_url = "#{@cognito_domain}/oauth2/token"

      create_mock(fn ->
        :meck.expect(Req, :post, fn url, opts ->
          if url == token_url do
            {:ok, %Req.Response{status: 400, body: error_response}}
          else
            :meck.passthrough([Req, :post, url, opts])
          end
        end)
      end)

      assert {:error, {:api_error, 400, body}} = CognitoClient.exchange_code_for_tokens(code, redirect_uri)
      assert body == error_response
    end

    test "handles network error" do
      code = "test-code"
      redirect_uri = @redirect_uri

      token_url = "#{@cognito_domain}/oauth2/token"

      create_mock(fn ->
        :meck.expect(Req, :post, fn url, opts ->
          if url == token_url do
            {:error, :timeout}
          else
            :meck.passthrough([Req, :post, url, opts])
          end
        end)
      end)

      assert {:error, :timeout} = CognitoClient.exchange_code_for_tokens(code, redirect_uri)
    end

    test "returns error when configuration is missing" do
      # Clear config
      Application.put_env(:journal, :cognito, nil)

      assert {:error, :configuration_not_found} =
               CognitoClient.exchange_code_for_tokens("code", "redirect")
    end
  end

  describe "get_user_info/1" do
    test "successfully gets user info from access token" do
      access_token = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."

      expected_response = %{
        "sub" => "cognito-user-123",
        "email" => "user@example.com",
        "name" => "John Doe",
        "email_verified" => true
      }

      userinfo_url = "#{@cognito_domain}/oauth2/userInfo"

      create_mock(fn ->
        :meck.expect(Req, :get, fn url, opts ->
          if url == userinfo_url do
            {:ok, %Req.Response{status: 200, body: expected_response}}
          else
            :meck.passthrough([Req, :get, url, opts])
          end
        end)
      end)

      assert {:ok, user_info} = CognitoClient.get_user_info(access_token)

      assert user_info["sub"] == expected_response["sub"]
      assert user_info["email"] == expected_response["email"]
      assert user_info["name"] == expected_response["name"]
    end

    test "handles API error response" do
      access_token = "invalid-token"

      error_response = %{
        "error" => "invalid_token",
        "error_description" => "The access token provided is expired, revoked, malformed, or invalid"
      }

      userinfo_url = "#{@cognito_domain}/oauth2/userInfo"

      create_mock(fn ->
        :meck.expect(Req, :get, fn url, opts ->
          if url == userinfo_url do
            {:ok, %Req.Response{status: 401, body: error_response}}
          else
            :meck.passthrough([Req, :get, url, opts])
          end
        end)
      end)

      assert {:error, {:api_error, 401, body}} = CognitoClient.get_user_info(access_token)
      assert body == error_response
    end

    test "handles network error" do
      access_token = "test-token"

      userinfo_url = "#{@cognito_domain}/oauth2/userInfo"

      create_mock(fn ->
        :meck.expect(Req, :get, fn url, opts ->
          if url == userinfo_url do
            {:error, :econnrefused}
          else
            :meck.passthrough([Req, :get, url, opts])
          end
        end)
      end)

      assert {:error, :econnrefused} = CognitoClient.get_user_info(access_token)
    end

    test "returns error when configuration is missing" do
      # Clear config
      Application.put_env(:journal, :cognito, nil)

      assert {:error, :configuration_not_found} = CognitoClient.get_user_info("token")
    end
  end

  describe "refresh_access_token/1" do
    test "successfully refreshes access token" do
      refresh_token = "refresh-token-123"

      expected_response = %{
        "access_token" => "new-access-token",
        "id_token" => "new-id-token",
        "expires_in" => 3600,
        "token_type" => "Bearer"
      }

      token_url = "#{@cognito_domain}/oauth2/token"

      create_mock(fn ->
        :meck.expect(Req, :post, fn url, opts ->
          if url == token_url do
            {:ok, %Req.Response{status: 200, body: expected_response}}
          else
            :meck.passthrough([Req, :post, url, opts])
          end
        end)
      end)

      assert {:ok, tokens} = CognitoClient.refresh_access_token(refresh_token)

      assert tokens.access_token == expected_response["access_token"]
      assert tokens.expires_in == expected_response["expires_in"]
      assert tokens.token_type == expected_response["token_type"]
    end

    test "handles API error response" do
      refresh_token = "invalid-refresh-token"

      error_response = %{
        "error" => "invalid_grant",
        "error_description" => "Invalid refresh token"
      }

      token_url = "#{@cognito_domain}/oauth2/token"

      create_mock(fn ->
        :meck.expect(Req, :post, fn url, opts ->
          if url == token_url do
            {:ok, %Req.Response{status: 400, body: error_response}}
          else
            :meck.passthrough([Req, :post, url, opts])
          end
        end)
      end)

      assert {:error, {:api_error, 400, body}} = CognitoClient.refresh_access_token(refresh_token)
      assert body == error_response
    end

    test "handles network error" do
      refresh_token = "test-refresh-token"

      token_url = "#{@cognito_domain}/oauth2/token"

      create_mock(fn ->
        :meck.expect(Req, :post, fn url, opts ->
          if url == token_url do
            {:error, :timeout}
          else
            :meck.passthrough([Req, :post, url, opts])
          end
        end)
      end)

      assert {:error, :timeout} = CognitoClient.refresh_access_token(refresh_token)
    end

    test "returns error when configuration is missing" do
      # Clear config
      Application.put_env(:journal, :cognito, nil)

      assert {:error, :configuration_not_found} = CognitoClient.refresh_access_token("token")
    end
  end

  # Private helper functions

  defp create_mock(setup_fun, retries \\ 3) do
    case :meck.new(Req, [:passthrough]) do
      :ok ->
        setup_fun.()
        :ok

      {:error, {:already_started, _}} when retries > 0 ->
        cleanup_mock_safely()
        :timer.sleep(5)
        create_mock(setup_fun, retries - 1)

      error ->
        raise "Failed to create mock after retries: #{inspect(error)}"
    end
  end

  defp cleanup_mock_safely do
    try do
      :meck.unload(Req)
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end
  end
end
