defmodule JournalWeb.Plugs.VerifyTokenTest do
  @moduledoc """
  Tests for VerifyToken plug.

  Tests cover:
  - Valid token validation and user lookup
  - Missing authorization header
  - Invalid token format
  - Token with missing kid
  - Token with invalid signature
  - Token with missing sub claim
  - User not found scenario
  - Patient ID extraction

  Note: Some tests use self-signed JWT tokens generated with RSA keys
  for comprehensive testing of the validation flow.
  """
  use JournalWeb.ConnCase, async: false

  import Plug.Conn

  alias Journal.Auth
  alias Journal.Auth.JWKS
  alias JournalWeb.Plugs.VerifyToken

  @cognito_domain "https://test-domain.auth.us-east-2.amazoncognito.com"
  @test_kid "test-key-id"

  setup do
    # Save original config
    original_config = Application.get_env(:journal, :cognito)

    # Set test config
    Application.put_env(:journal, :cognito, [
      domain: @cognito_domain
    ])

    # Clean up any existing mocks
    cleanup_mock_safely()

    on_exit(fn ->
      cleanup_mock_safely()
      # Restore original config
      Application.put_env(:journal, :cognito, original_config)
    end)

    # Create test user and patient
    {:ok, user} = Auth.create_or_find_user("test-cognito-id", %{
      name: "Test User",
      email: "test@example.com"
    })

    {:ok, patient} = Auth.create_patient(user.id, 1)

    {:ok, user: user, patient: patient}
  end

  describe "call/2" do
    test "returns 401 when token validation fails due to JWKS error", %{conn: conn} do
      token = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6InRlc3Qta2lkIn0.eyJzdWIiOiJ0ZXN0LWNvZ25pdG8taWQiLCJleHAiOjk5OTk5OTk5OTl9.fake-signature"
      mock_jwks_error()

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> VerifyToken.call([])

      assert conn.status == 401
      assert conn.halted

      response = Jason.decode!(conn.resp_body)
      assert response["error"] == "Invalid token"
    end

    test "returns 401 when authorization header is missing", %{conn: conn} do
      conn = VerifyToken.call(conn, [])

      assert conn.status == 401
      assert conn.halted

      response = Jason.decode!(conn.resp_body)
      assert response["error"] == "Missing authorization header"
    end

    test "returns 401 when authorization header is invalid format", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "InvalidFormat token")
        |> VerifyToken.call([])

      assert conn.status == 401
      assert conn.halted

      response = Jason.decode!(conn.resp_body)
      assert response["error"] == "Missing authorization header"
    end

    test "returns 401 when token format is invalid", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid.token")
        |> VerifyToken.call([])

      assert conn.status == 401
      assert conn.halted

      response = Jason.decode!(conn.resp_body)
      assert response["error"] == "Invalid token"
    end

    test "returns 401 when token header is missing kid", %{conn: conn} do
      # Create token without kid in header (base64 encoded JSON)
      header_json = Jason.encode!(%{"alg" => "RS256", "typ" => "JWT"})
      payload_json = Jason.encode!(%{"sub" => "test-cognito-id", "exp" => :os.system_time(:second) + 3600})

      header_b64 = Base.url_encode64(header_json, padding: false)
      payload_b64 = Base.url_encode64(payload_json, padding: false)
      signature_b64 = "fake-signature"

      token = "#{header_b64}.#{payload_b64}.#{signature_b64}"

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> VerifyToken.call([])

      assert conn.status == 401
      assert conn.halted

      response = Jason.decode!(conn.resp_body)
      assert response["error"] == "Invalid token"
    end

    test "returns 401 when JWKS fetch fails", %{conn: conn} do
      # Token with kid in header
      token = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6InRlc3Qta2lkIn0.eyJzdWIiOiJ0ZXN0LWNvZ25pdG8taWQiLCJleHAiOjk5OTk5OTk5OTl9.fake-signature"
      mock_jwks_error()

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> VerifyToken.call([])

      assert conn.status == 401
      assert conn.halted

      response = Jason.decode!(conn.resp_body)
      assert response["error"] == "Invalid token"
    end

    test "returns 401 when token signature is invalid", %{conn: conn} do
      # Generate a token with one key, but mock JWKS to return a different key
      # This will cause signature validation to fail
      {token, _jwk1} = generate_signed_token("test-cognito-id", @test_kid)

      # Generate a different key for JWKS (signature won't match)
      public_jwk2 = JOSE.JWK.generate_key({:rsa, 2048})
      |> JOSE.JWK.to_public()
      {_alg, jwk2_map} = JOSE.JWK.to_map(public_jwk2)
      jwk2_map_with_kid = Map.put(jwk2_map, "kid", @test_kid)

      mock_jwks_success(@test_kid, jwk2_map_with_kid)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> VerifyToken.call([])

      assert conn.status == 401
      assert conn.halted

      response = Jason.decode!(conn.resp_body)
      assert response["error"] == "Invalid token"
    end

    test "successfully validates token and sets assigns", %{conn: conn, user: user, patient: patient} do
      {token, jwk} = generate_signed_token("test-cognito-id", @test_kid)
      mock_jwks_success(@test_kid, jwk)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> VerifyToken.call([])

      assert conn.assigns[:current_user].id == user.id
      assert conn.assigns[:current_patient_id] == patient.id
      refute conn.halted
    end

    test "returns 404 when user is not found", %{conn: conn} do
      {token, jwk} = generate_signed_token("non-existent-cognito-id", @test_kid)
      mock_jwks_success(@test_kid, jwk)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> VerifyToken.call([])

      assert conn.status == 404
      assert conn.halted

      response = Jason.decode!(conn.resp_body)
      assert response["error"] == "User not found"
    end

    test "handles user without patient", %{conn: conn} do
      # Create user without patient
      {:ok, user_without_patient} = Auth.create_or_find_user("no-patient-cognito-id", %{
        name: "No Patient User",
        email: "nopatient-#{System.unique_integer([:positive])}@example.com"
      })

      {token, jwk} = generate_signed_token("no-patient-cognito-id", @test_kid)
      mock_jwks_success(@test_kid, jwk)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> VerifyToken.call([])

      assert conn.assigns[:current_user].id == user_without_patient.id
      assert conn.assigns[:current_patient_id] == nil
      refute conn.halted
    end

    test "returns 401 when token has invalid format (not 3 parts)", %{conn: conn} do
      token = "invalid.token"

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> VerifyToken.call([])

      assert conn.status == 401
      assert conn.halted

      response = Jason.decode!(conn.resp_body)
      assert response["error"] == "Invalid token"
    end

    test "returns 401 when token has expired", %{conn: conn} do
      # Generate token with expired exp claim
      now = System.system_time(:second)
      expired_claims = %{
        "sub" => "test-cognito-id",
        "exp" => now - 3600,  # Expired 1 hour ago
        "iat" => now - 7200
      }
      {token, jwk} = generate_signed_token_with_claims(expired_claims, @test_kid)
      mock_jwks_success(@test_kid, jwk)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> VerifyToken.call([])

      assert conn.status == 401
      assert conn.halted

      response = Jason.decode!(conn.resp_body)
      assert response["error"] == "Token expired"
    end

    test "returns 401 when token has nbf claim in the future", %{conn: conn} do
      # Generate token with nbf claim in the future
      now = System.system_time(:second)
      future_claims = %{
        "sub" => "test-cognito-id",
        "exp" => now + 3600,
        "iat" => now,
        "nbf" => now + 1800  # Not valid for another 30 minutes
      }
      {token, jwk} = generate_signed_token_with_claims(future_claims, @test_kid)
      mock_jwks_success(@test_kid, jwk)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> VerifyToken.call([])

      assert conn.status == 401
      assert conn.halted

      response = Jason.decode!(conn.resp_body)
      assert response["error"] == "Token not yet valid"
    end

    test "accepts token with missing exp claim", %{conn: conn, user: user, patient: patient} do
      # Generate token without exp claim (should still be accepted)
      claims = %{
        "sub" => "test-cognito-id",
        "iat" => System.system_time(:second)
        # No exp claim - token should still be accepted
      }
      {token, jwk} = generate_signed_token_with_claims(claims, @test_kid)
      mock_jwks_success(@test_kid, jwk)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> VerifyToken.call([])

      # Token without exp should be accepted (exp is optional in some cases)
      assert conn.assigns[:current_user].id == user.id
      assert conn.assigns[:current_patient_id] == patient.id
      refute conn.halted
    end
  end

  # Private helper functions

  defp generate_signed_token(cognito_id, kid) do
    now = System.system_time(:second)
    claims = %{
      "sub" => cognito_id,
      "exp" => now + 3600,
      "iat" => now,
      "nbf" => now
    }
    generate_signed_token_with_claims(claims, kid)
  end

  defp generate_signed_token_with_claims(claims, kid) do
    # Generate RSA key pair using JOSE
    private_jwk = JOSE.JWK.generate_key({:rsa, 2048})

    # Get public key
    public_jwk = JOSE.JWK.to_public(private_jwk)

    # Create header with kid from the start
    header = %{
      "alg" => "RS256",
      "typ" => "JWT",
      "kid" => kid
    }

    # Sign token using JOSE directly with kid in header
    {_alg, token} = JOSE.JWT.sign(private_jwk, header, claims)
    |> JOSE.JWS.compact()

    # Convert JOSE JWK to map format for JWKS
    # Ensure all required fields are present
    {_alg, jwk_map} = JOSE.JWK.to_map(public_jwk)
    jwk_map_with_kid = jwk_map
      |> Map.put("kid", kid)
      |> Map.put("use", "sig")  # Add use field for key operations
      |> Map.put("alg", "RS256")  # Add algorithm hint

    {token, jwk_map_with_kid}
  end

  defp mock_jwks_success(kid, jwk_map) do
    create_mock(fn ->
      :meck.expect(JWKS, :get_public_key, fn ^kid ->
        # Return the JWK map - the plug will convert it to JOSE JWK
        {:ok, jwk_map}
      end)
    end)
  end

  defp mock_jwks_error do
    create_mock(fn ->
      :meck.expect(JWKS, :get_public_key, fn _kid ->
        {:error, :timeout}
      end)
    end)
  end

  defp create_mock(setup_fun, retries \\ 3) do
    case :meck.new(JWKS, [:passthrough]) do
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
      :meck.unload(JWKS)
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end
  end
end
