defmodule Journal.Auth.JWKS do
  @moduledoc """
  Fetches and caches JSON Web Key Set (JWKS) from Cognito for JWT token validation.

  This module provides functions to:
  - Fetch JWKS from Cognito's well-known endpoint
  - Cache JWKS keys to avoid repeated HTTP requests
  - Get the appropriate public key for a given key ID (kid)

  The JWKS is cached for 24 hours and refreshed automatically when needed.
  """

  require Logger

  @cache_ttl 24 * 60 * 60 * 1000 # 24 hours in milliseconds
  @min_refresh_interval 30 * 1000 # 30 seconds in milliseconds

  @doc """
  Gets the public key for a given key ID (kid) from Cognito JWKS.

  Fetches JWKS from Cognito if not cached or if cache is expired.
  Caches the keys to avoid repeated HTTP requests.

  ## Parameters
    - `kid`: The key ID from the JWT token header

  ## Returns
    - `{:ok, public_key}` where public_key is a JOSE public key map
    - `{:error, reason}` on failure

  ## Examples

      iex> JWKS.get_public_key("abc123")
      {:ok, %{"kty" => "RSA", "n" => "...", "e" => "AQAB"}}
  """
  def get_public_key(kid) do
    case fetch_jwks() do
      {:ok, jwks} ->
        case find_key_by_kid(jwks, kid) do
          nil ->
            Logger.error("Key ID #{kid} not found in JWKS")
            {:error, :key_not_found}

          key ->
            {:ok, key}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetches JWKS from Cognito's well-known endpoint.

  Uses caching to avoid repeated HTTP requests. Cache is refreshed if:
  - No cache exists
  - Cache is older than 24 hours
  - At least 30 seconds have passed since last fetch (prevents abuse)

  ## Returns
    - `{:ok, jwks}` where jwks is a list of key maps
    - `{:error, reason}` on failure

  ## Examples

      iex> JWKS.fetch_jwks()
      {:ok, [%{"kid" => "abc123", "kty" => "RSA", ...}, ...]}
  """
  def fetch_jwks do
    config = get_config()

    if config do
      jwks_url = build_jwks_url(config)
      cache_key = :jwks_cache

      # Check cache
      case :persistent_term.get(cache_key, nil) do
        {jwks, timestamp} ->
          now = System.system_time(:millisecond)
          age = now - timestamp

          # Use cache if less than TTL old and at least min_refresh_interval has passed
          if age < @cache_ttl do
            Logger.debug("Using cached JWKS (age: #{age}ms)")
            {:ok, jwks}
          else
            # Cache expired, but check if we can refresh
            if age >= @min_refresh_interval do
              Logger.info("JWKS cache expired, fetching new keys")
              do_fetch_jwks(jwks_url, cache_key)
            else
              # Too soon to refresh, use stale cache
              Logger.debug("Using stale JWKS cache (too soon to refresh)")
              {:ok, jwks}
            end
          end

        nil ->
          # No cache, fetch immediately
          Logger.info("No JWKS cache found, fetching from Cognito")
          do_fetch_jwks(jwks_url, cache_key)
      end
    else
      Logger.error("Cognito configuration not found")
      {:error, :configuration_not_found}
    end
  end

  # Private functions

  defp do_fetch_jwks(jwks_url, cache_key) do
    case Req.get(jwks_url, receive_timeout: 10_000) do
      {:ok, %Req.Response{status: 200, body: %{"keys" => keys}}} ->
        timestamp = System.system_time(:millisecond)
        :persistent_term.put(cache_key, {keys, timestamp})
        Logger.info("Successfully fetched and cached JWKS (#{length(keys)} keys)")
        {:ok, keys}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Failed to fetch JWKS: status #{status}, body: #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("Failed to fetch JWKS: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp find_key_by_kid(keys, kid) do
    Enum.find(keys, fn key -> Map.get(key, "kid") == kid end)
  end

  defp get_config do
    config = Application.get_env(:journal, :cognito)

    if config do
      %{
        domain: config[:domain],
        user_pool_id: config[:user_pool_id] || extract_user_pool_id_from_domain(config[:domain]),
        region: config[:region] || extract_region_from_domain(config[:domain])
      }
    else
      nil
    end
  end

  defp build_jwks_url(config) do
    # JWKS URL format: https://cognito-idp.{region}.amazonaws.com/{userPoolId}/.well-known/jwks.json
    if config.user_pool_id && config.region do
      "https://cognito-idp.#{config.region}.amazonaws.com/#{config.user_pool_id}/.well-known/jwks.json"
    else
      # Fallback to Hosted UI domain (may not work for all Cognito setups)
      domain = String.trim_trailing(config.domain || "", "/")
      "#{domain}/.well-known/jwks.json"
    end
  end

  defp extract_user_pool_id_from_domain(domain) when is_binary(domain) do
    # Try to extract from domain or use environment variable
    System.get_env("COGNITO_USER_POOL_ID")
  end

  defp extract_user_pool_id_from_domain(_), do: nil

  defp extract_region_from_domain(domain) when is_binary(domain) do
    # Extract region from domain like: https://xxx.auth.us-east-2.amazoncognito.com
    case Regex.run(~r/\.auth\.([^.]+)\.amazoncognito\.com/, domain) do
      [_, region] -> region
      _ -> System.get_env("AWS_REGION") || "us-east-2"
    end
  end

  defp extract_region_from_domain(_), do: System.get_env("AWS_REGION") || "us-east-2"
end
