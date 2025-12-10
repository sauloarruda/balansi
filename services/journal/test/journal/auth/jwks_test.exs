defmodule Journal.Auth.JWKSTest do
  @moduledoc """
  Tests for JWKS module.

  Tests cover:
  - Fetching JWKS from Cognito
  - Caching JWKS keys
  - Getting public key by kid
  - Error handling for various failure scenarios
  - Configuration validation
  """
  use ExUnit.Case, async: false

  alias Journal.Auth.JWKS

  @cognito_domain "https://test-domain.auth.us-east-2.amazoncognito.com"

  setup do
    # Save original config
    original_config = Application.get_env(:journal, :cognito)

    # Set test config
    Application.put_env(:journal, :cognito, [
      domain: @cognito_domain
    ])

    # Clear cache
    clear_jwks_cache()

    # Clean up any existing mocks
    cleanup_mock_safely()

    on_exit(fn ->
      cleanup_mock_safely()
      clear_jwks_cache()
      # Restore original config
      Application.put_env(:journal, :cognito, original_config)
    end)

    :ok
  end

  describe "fetch_jwks/0" do
    test "successfully fetches JWKS from Cognito" do
      jwks_url = "#{@cognito_domain}/.well-known/jwks.json"

      expected_jwks = %{
        "keys" => [
          %{
            "kid" => "key-id-1",
            "kty" => "RSA",
            "n" => "test-n-value",
            "e" => "AQAB"
          },
          %{
            "kid" => "key-id-2",
            "kty" => "RSA",
            "n" => "test-n-value-2",
            "e" => "AQAB"
          }
        ]
      }

      create_mock(fn ->
        :meck.expect(Req, :get, fn url, opts ->
          if url == jwks_url do
            {:ok, %Req.Response{status: 200, body: expected_jwks}}
          else
            :meck.passthrough([Req, :get, url, opts])
          end
        end)
      end)

      assert {:ok, keys} = JWKS.fetch_jwks()
      assert length(keys) == 2
      assert Enum.any?(keys, fn key -> Map.get(key, "kid") == "key-id-1" end)
      assert Enum.any?(keys, fn key -> Map.get(key, "kid") == "key-id-2" end)
    end

    test "caches JWKS after first fetch" do
      jwks_url = "#{@cognito_domain}/.well-known/jwks.json"

      expected_jwks = %{
        "keys" => [
          %{
            "kid" => "key-id-1",
            "kty" => "RSA",
            "n" => "test-n-value",
            "e" => "AQAB"
          }
        ]
      }

      call_count = Agent.start_link(fn -> 0 end) |> elem(1)

      create_mock(fn ->
        :meck.expect(Req, :get, fn url, opts ->
          if url == jwks_url do
            Agent.update(call_count, fn count -> count + 1 end)
            {:ok, %Req.Response{status: 200, body: expected_jwks}}
          else
            :meck.passthrough([Req, :get, url, opts])
          end
        end)
      end)

      # First fetch
      assert {:ok, _keys} = JWKS.fetch_jwks()
      assert Agent.get(call_count, fn count -> count end) == 1

      # Second fetch should use cache
      assert {:ok, _keys} = JWKS.fetch_jwks()
      assert Agent.get(call_count, fn count -> count end) == 1
    end

    test "handles API error response" do
      jwks_url = "#{@cognito_domain}/.well-known/jwks.json"

      error_response = %{
        "error" => "not_found",
        "error_description" => "JWKS not found"
      }

      create_mock(fn ->
        :meck.expect(Req, :get, fn url, opts ->
          if url == jwks_url do
            {:ok, %Req.Response{status: 404, body: error_response}}
          else
            :meck.passthrough([Req, :get, url, opts])
          end
        end)
      end)

      assert {:error, {:api_error, 404, body}} = JWKS.fetch_jwks()
      assert body == error_response
    end

    test "handles network error" do
      jwks_url = "#{@cognito_domain}/.well-known/jwks.json"

      create_mock(fn ->
        :meck.expect(Req, :get, fn url, opts ->
          if url == jwks_url do
            {:error, :timeout}
          else
            :meck.passthrough([Req, :get, url, opts])
          end
        end)
      end)

      assert {:error, :timeout} = JWKS.fetch_jwks()
    end

    test "returns error when configuration is missing" do
      # Clear config
      Application.put_env(:journal, :cognito, nil)

      assert {:error, :configuration_not_found} = JWKS.fetch_jwks()
    end
  end

  describe "get_public_key/1" do
    test "successfully gets public key by kid" do
      jwks_url = "#{@cognito_domain}/.well-known/jwks.json"

      expected_jwks = %{
        "keys" => [
          %{
            "kid" => "key-id-1",
            "kty" => "RSA",
            "n" => "test-n-value",
            "e" => "AQAB"
          },
          %{
            "kid" => "key-id-2",
            "kty" => "RSA",
            "n" => "test-n-value-2",
            "e" => "AQAB"
          }
        ]
      }

      create_mock(fn ->
        :meck.expect(Req, :get, fn url, opts ->
          if url == jwks_url do
            {:ok, %Req.Response{status: 200, body: expected_jwks}}
          else
            :meck.passthrough([Req, :get, url, opts])
          end
        end)
      end)

      assert {:ok, key} = JWKS.get_public_key("key-id-1")
      assert Map.get(key, "kid") == "key-id-1"
      assert Map.get(key, "kty") == "RSA"
    end

    test "returns error when kid not found" do
      jwks_url = "#{@cognito_domain}/.well-known/jwks.json"

      expected_jwks = %{
        "keys" => [
          %{
            "kid" => "key-id-1",
            "kty" => "RSA",
            "n" => "test-n-value",
            "e" => "AQAB"
          }
        ]
      }

      create_mock(fn ->
        :meck.expect(Req, :get, fn url, opts ->
          if url == jwks_url do
            {:ok, %Req.Response{status: 200, body: expected_jwks}}
          else
            :meck.passthrough([Req, :get, url, opts])
          end
        end)
      end)

      assert {:error, :key_not_found} = JWKS.get_public_key("non-existent-kid")
    end

    test "handles JWKS fetch error" do
      jwks_url = "#{@cognito_domain}/.well-known/jwks.json"

      create_mock(fn ->
        :meck.expect(Req, :get, fn url, opts ->
          if url == jwks_url do
            {:error, :timeout}
          else
            :meck.passthrough([Req, :get, url, opts])
          end
        end)
      end)

      assert {:error, :timeout} = JWKS.get_public_key("key-id-1")
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

  defp clear_jwks_cache do
    try do
      :persistent_term.erase(:jwks_cache)
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end
  end
end
