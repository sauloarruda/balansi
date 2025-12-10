defmodule JournalWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use JournalWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias Journal.Auth.JWKS

  using do
    quote do
      # The default endpoint for testing
      @endpoint JournalWeb.Endpoint

      use JournalWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import JournalWeb.ConnCase
    end
  end

  setup tags do
    Journal.DataCase.setup_sandbox(tags)
    # Ensure default test patients exist (required for foreign key constraints)
    Journal.DataCase.ensure_test_patients()
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Sets up an authenticated connection for testing protected routes.

  Creates a user and patient in the database, generates a valid JWT token,
  mocks JWKS to validate the token, and sets the Authorization header.
  This allows the VerifyToken plug to validate the token and set assigns.

  ## Parameters
    - `conn` - The connection to authenticate
    - `opts` - Optional keyword list:
      - `:cognito_id` - Cognito ID for the user (default: auto-generated)
      - `:patient_id` - Specific patient ID to use (default: creates new patient)

  ## Returns
    - `{conn, patient_id}` - Tuple with authenticated connection and patient_id

  ## Example

      test "creates meal with authenticated user", %{conn: conn} do
        {conn, patient_id} = authenticate_conn(conn)

        conn = post(conn, ~p"/journal/meals", %{"meal_type" => "breakfast", ...})
        # ...
      end
  """
  def authenticate_conn(conn, opts \\ []) do
    alias Journal.Auth
    alias Journal.Auth.JWKS

    cognito_id = Keyword.get(opts, :cognito_id, "test-cognito-#{System.unique_integer([:positive])}")
    patient_id = Keyword.get(opts, :patient_id)
    test_kid = "test-key-id-#{System.unique_integer([:positive])}"

    # Create user
    {:ok, user} = Auth.create_or_find_user(cognito_id, %{
      name: "Test User",
      email: "test-#{System.unique_integer([:positive])}@example.com"
    })

    # Create or get patient
    patient = if patient_id do
      # Get existing patient if ID provided
      alias Journal.Auth.Patient
      case Journal.Repo.get(Patient, patient_id) do
        nil ->
          {:ok, p} = Auth.create_patient(user.id, 1)
          p
        existing_patient ->
          existing_patient
      end
    else
      # Create new patient
      {:ok, p} = Auth.create_patient(user.id, 1)
      p
    end

    # Generate signed token
    {token, jwk_map} = generate_signed_token(cognito_id, test_kid)

    # Mock JWKS to return the public key
    mock_jwks_success(test_kid, jwk_map)

    # Set Authorization header
    conn = conn
    |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")

    {conn, patient.id}
  end

  # Private helper functions for token generation

  defp generate_signed_token(cognito_id, kid) do
    now = System.system_time(:second)
    claims = %{
      "sub" => cognito_id,
      "exp" => now + 3600,
      "iat" => now,
      "nbf" => now
    }

    # Generate RSA key pair using JOSE
    private_jwk = JOSE.JWK.generate_key({:rsa, 2048})
    public_jwk = JOSE.JWK.to_public(private_jwk)

    # Create header with kid
    header = %{
      "alg" => "RS256",
      "typ" => "JWT",
      "kid" => kid
    }

    # Sign token
    {_alg, token} = JOSE.JWT.sign(private_jwk, header, claims)
    |> JOSE.JWS.compact()

    # Convert JOSE JWK to map format for JWKS
    {_alg, jwk_map} = JOSE.JWK.to_map(public_jwk)
    jwk_map_with_kid = jwk_map
      |> Map.put("kid", kid)
      |> Map.put("use", "sig")
      |> Map.put("alg", "RS256")

    {token, jwk_map_with_kid}
  end

  defp mock_jwks_success(kid, jwk_map) do
    # Use meck to mock JWKS.get_public_key
    # Clean up any existing mock first
    cleanup_mock_safely()

    case :meck.new(JWKS, [:passthrough]) do
      :ok ->
        :meck.expect(JWKS, :get_public_key, fn ^kid ->
          {:ok, jwk_map}
        end)
        :ok

      {:error, {:already_started, _}} ->
        # Try to unload and retry
        cleanup_mock_safely()
        :timer.sleep(5)
        case :meck.new(JWKS, [:passthrough]) do
          :ok ->
            :meck.expect(JWKS, :get_public_key, fn ^kid ->
              {:ok, jwk_map}
            end)
            :ok
          error ->
            raise "Failed to create JWKS mock after cleanup: #{inspect(error)}"
        end

      error ->
        raise "Failed to create JWKS mock: #{inspect(error)}"
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
