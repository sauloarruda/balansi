defmodule Journal.Auth.Session do
  @moduledoc """
  Session management for encrypted storage of authentication data in cookies.

  This module encrypts sensitive session data (refresh token, user ID) before
  storing it in cookies, following the same pattern as the Go auth service.

  The encrypted session data is stored in a cookie and can only be decrypted
  by the server using the encryption secret.
  """

  require Logger

  @doc """
  Encrypts session data for storage in a cookie.

  ## Parameters
    - `refresh_token`: The Cognito refresh token
    - `user_id`: The user ID from the database

  ## Returns
    - `{:ok, encrypted_data}` where encrypted_data is a base64-encoded string
    - `{:error, reason}` on encryption failure

  ## Examples

      iex> Session.encrypt_session("refresh-token-123", 1)
      {:ok, "encrypted-base64-string..."}
  """
  def encrypt_session(refresh_token, user_id) do
    secret = get_encryption_secret()

    if secret do
      session_data = %{
        refresh_token: refresh_token,
        user_id: user_id
      }

      json_data = Jason.encode!(session_data)

      # Use a salt derived from the secret for encryption
      # This ensures consistent encryption/decryption
      salt = get_encryption_salt(secret)

      try do
        encrypted = Plug.Crypto.encrypt(json_data, secret, salt)
        {:ok, Base.url_encode64(encrypted)}
      rescue
        e ->
          Logger.error("Failed to encrypt session data: #{inspect(e)}")
          {:error, :encryption_failed}
      end
    else
      Logger.error("Encryption secret not configured")
      {:error, :configuration_not_found}
    end
  end

  @doc """
  Decrypts session data from a cookie.

  ## Parameters
    - `encrypted_data`: Base64-encoded encrypted session data from cookie

  ## Returns
    - `{:ok, session_data}` where session_data is a map with:
      - `refresh_token`: The Cognito refresh token
      - `user_id`: The user ID from the database
    - `{:error, reason}` on decryption failure

  ## Examples

      iex> Session.decrypt_session("encrypted-base64-string...")
      {:ok, %{refresh_token: "refresh-token-123", user_id: 1}}
  """
  def decrypt_session(encrypted_data) do
    secret = get_encryption_secret()

    if secret do
      case Base.url_decode64(encrypted_data) do
        {:ok, decoded} ->
          salt = get_encryption_salt(secret)

          try do
            decrypted = Plug.Crypto.decrypt(decoded, secret, salt)

            case Jason.decode(decrypted) do
              {:ok, session_data} ->
                {:ok, atomize_keys(session_data)}

              {:error, reason} ->
                Logger.error("Failed to decode session JSON: #{inspect(reason)}")
                {:error, :invalid_session_data}
            end
          rescue
            e ->
              Logger.error("Failed to decrypt session data: #{inspect(e)}")
              {:error, :decryption_failed}
          end

        :error ->
          Logger.error("Failed to decode base64 session data")
          {:error, :invalid_encoding}
      end
    else
      Logger.error("Encryption secret not configured")
      {:error, :configuration_not_found}
    end
  end

  # Private functions

  defp get_encryption_secret do
    # Use SECRET_KEY_BASE from endpoint config, or a dedicated SESSION_ENCRYPTION_SECRET
    # Prefer dedicated secret if available, fallback to SECRET_KEY_BASE
    case System.get_env("SESSION_ENCRYPTION_SECRET") do
      nil ->
        # Fallback to secret_key_base from endpoint config
        Application.get_env(:journal, JournalWeb.Endpoint)[:secret_key_base]

      secret ->
        secret
    end
  end

  defp get_encryption_salt(secret) do
    # Derive a consistent salt from the secret using SHA256
    # This ensures the same secret always produces the same salt
    :crypto.hash(:sha256, secret <> "session_salt")
    |> :binary.part(0, 16)  # Use first 16 bytes as salt
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {"refresh_token", value} ->
        {:refresh_token, value}

      {"user_id", value} ->
        {:user_id, value}

      {key, value} ->
        {key, value}
    end)
  end
end
