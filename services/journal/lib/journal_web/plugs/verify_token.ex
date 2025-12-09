defmodule JournalWeb.Plugs.VerifyToken do
  @moduledoc """
  Plug for validating JWT access tokens from Cognito.

  This plug:
  1. Extracts Bearer token from Authorization header
  2. Validates JWT token signature using Cognito JWKS
  3. Extracts cognito_id (sub claim) from token
  4. Looks up user in database by cognito_id
  5. Gets patient_id from user's patient record
  6. Adds `current_user` and `current_patient_id` to conn.assigns

  If validation fails at any step, returns 401 Unauthorized and halts the connection.

  ## Usage

      pipeline :protected do
        plug VerifyToken
      end

      scope "/api", MyAppWeb do
        pipe_through :protected
        # Protected routes here
      end
  """

  import Plug.Conn
  import Phoenix.Controller
  require Logger

  alias Journal.Auth.JWKS
  alias Journal.Repo

  def init(opts), do: opts

  def call(conn, _opts) do
    case extract_token(conn) do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Missing authorization header"})
        |> halt()

      token ->
        case validate_token(token) do
          {:ok, cognito_id} ->
            case get_user_by_cognito_id(cognito_id) do
              nil ->
                Logger.warning("User not found for cognito_id: #{cognito_id}")
                conn
                |> put_status(:not_found)
                |> json(%{error: "User not found"})
                |> halt()

              user ->
                patient_id = get_patient_id(user.id)

                conn
                |> assign(:current_user, user)
                |> assign(:current_patient_id, patient_id)
            end

          {:error, reason} ->
            Logger.warning("Token validation failed: #{inspect(reason)}")
            conn
            |> put_status(:unauthorized)
            |> json(%{error: "Invalid token"})
            |> halt()
        end
    end
  end

  # Private functions

  defp extract_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token
      _ -> nil
    end
  end

  defp validate_token(token_string) do
    with {:ok, kid} <- extract_kid_from_token(token_string),
         {:ok, jwk} <- JWKS.get_public_key(kid),
         {:ok, claims} <- verify_token_signature(token_string, jwk),
         {:ok, cognito_id} <- extract_cognito_id(claims) do
      {:ok, cognito_id}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_kid_from_token(token_string) do
    case String.split(token_string, ".") do
      [header_b64, _payload_b64, _signature_b64] ->
        case Base.url_decode64(header_b64, padding: false) do
          {:ok, header_json} ->
            case Jason.decode(header_json) do
              {:ok, %{"kid" => kid}} when is_binary(kid) and kid != "" ->
                {:ok, kid}

              {:ok, _header} ->
                {:error, :missing_kid}

              {:error, reason} ->
                {:error, {:invalid_header, reason}}
            end

          :error ->
            {:error, :invalid_header_encoding}
        end

      _ ->
        {:error, :invalid_token_format}
    end
  end

  defp verify_token_signature(token_string, jwk) do
    # Convert JWK map to JOSE JWK format
    jose_jwk = JOSE.JWK.from_map(jwk)

    # Verify token signature using JOSE directly
    case JOSE.JWT.verify_strict(jose_jwk, ["RS256"], token_string) do
      {true, jwt, _jws} ->
        # Extract claims from verified JWT
        claims = JOSE.JWT.to_map(jwt) |> elem(1)

        # Validate expiration manually (JOSE doesn't do this automatically)
        now = System.system_time(:second)
        exp = Map.get(claims, "exp")

        if exp && exp > now do
          {:ok, claims}
        else
          Logger.error("Token has expired or missing exp claim")
          {:error, :invalid_signature}
        end

      {false, _jwt, _jws} ->
        Logger.error("Token signature verification failed")
        {:error, :invalid_signature}
    end
  end

  defp extract_cognito_id(claims) do
    case Map.get(claims, "sub") do
      nil ->
        {:error, :missing_sub}

      cognito_id when is_binary(cognito_id) and cognito_id != "" ->
        {:ok, cognito_id}

      _ ->
        {:error, :invalid_sub}
    end
  end

  defp get_user_by_cognito_id(cognito_id) do
    alias Journal.Auth.User
    Repo.get_by(User, cognito_id: cognito_id)
  end

  defp get_patient_id(user_id) do
    alias Journal.Auth.Patient
    case Repo.get_by(Patient, user_id: user_id) do
      nil -> nil
      patient -> patient.id
    end
  end
end
