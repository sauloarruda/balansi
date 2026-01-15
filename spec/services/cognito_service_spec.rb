require "rails_helper"
require "ostruct"

RSpec.describe CognitoService, type: :service do
  include CognitoCredentialsHelper

  let(:test_credentials_hash) do
    {
      cognito: {
        user_pool_id: "sa-east-1_test_pool",
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        domain: "test-domain",
        region: "sa-east-1",
        redirect_uri: "http://localhost:3000/auth/callbacks",
        logout_uri: "http://localhost:3000/"
      }
    }
  end

  before do
    # Mock Rails.application.credentials to return test credentials
    mock_credentials

    # Clear cache before each test
    Rails.cache.clear
  end

  after do
    # Restore original method if it existed
    restore_credentials
    WebMock.reset!
  end

  describe ".credentials" do
    it "returns environment-specific credentials" do
      result = described_class.send(:credentials)
      expect(result.dig(:cognito, :client_id)).to eq("test_client_id")
    end

    it "falls back to default credentials when ArgumentError is raised" do
      call_count = 0
      test_hash = test_credentials_hash
      restore_credentials # Restore before setting custom mock
      Rails.application.define_singleton_method(:credentials) do |env = nil|
        call_count += 1
        if call_count == 1 && env == :test
          raise ArgumentError, "No credentials found"
        end
        creds = OpenStruct.new
        creds.define_singleton_method(:dig) do |*args|
          test_hash.dig(*args)
        end
        creds
      end

      result = described_class.send(:credentials)
      expect(result.dig(:cognito, :client_id)).to eq("test_client_id")
    end
  end

  describe ".cognito_language_code" do
    it "converts :pt to pt-BR" do
      expect(described_class.cognito_language_code(:pt)).to eq("pt-BR")
    end

    it "converts :en to en" do
      expect(described_class.cognito_language_code(:en)).to eq("en")
    end

    it "defaults to pt-BR for unknown locale" do
      expect(described_class.cognito_language_code(:fr)).to eq("pt-BR")
    end
  end

  describe ".login_url" do
    it "generates correct OAuth URL" do
      url = described_class.login_url
      expect(url).to include("/oauth2/authorize")
      expect(url).to include("client_id=test_client_id")
      expect(url).to include("response_type=code")
      expect(url).to include("redirect_uri=http%3A%2F%2Flocalhost%3A3000%2Fauth%2Fcallbacks")
      expect(url).to include("scope=openid+email+profile")
    end

    it "includes state parameter when provided" do
      state = "csrf_token=abc123"
      url = described_class.login_url(state: state)
      expect(url).to include("state=csrf_token%3Dabc123")
    end

    it "raises MissingCredentialsError when credentials not configured" do
      mock_credentials({})

      expect {
        described_class.login_url
      }.to raise_error(CognitoService::MissingCredentialsError, "Cognito credentials not configured")
    end
  end

  describe ".signup_url" do
    it "generates correct OAuth URL" do
      url = described_class.signup_url
      expect(url).to include("/oauth2/authorize")
      expect(url).to include("client_id=test_client_id")
      expect(url).to include("response_type=code")
    end

    it "includes state parameter when provided" do
      state = "csrf_token=xyz789"
      url = described_class.signup_url(state: state)
      expect(url).to include("state=csrf_token%3Dxyz789")
    end

    it "raises MissingCredentialsError when credentials not configured" do
      mock_credentials({})

      expect {
        described_class.signup_url
      }.to raise_error(CognitoService::MissingCredentialsError, "Cognito credentials not configured")
    end
  end

  describe ".logout_url" do
    it "generates correct logout URL" do
      url = described_class.logout_url
      expect(url).to include("/logout")
      expect(url).to include("client_id=test_client_id")
      expect(url).to include("logout_uri=http%3A%2F%2Flocalhost%3A3000%2F")
    end

    it "normalizes logout_uri to have trailing slash" do
      url = described_class.logout_url(logout_uri_param: "http://localhost:3000")
      expect(url).to include("logout_uri=http%3A%2F%2Flocalhost%3A3000%2F")
    end

    it "uses provided logout_uri_param" do
      url = described_class.logout_url(logout_uri_param: "http://example.com/logout")
      expect(url).to include("logout_uri=http%3A%2F%2Fexample.com%2Flogout%2F")
    end

    it "uses logout_uri from credentials when logout_uri_param is nil" do
      url = described_class.logout_url(logout_uri_param: nil)
      expect(url).to include("logout_uri=http%3A%2F%2Flocalhost%3A3000%2F")
    end

    it "falls back to redirect_uri when logout_uri not in credentials" do
      test_hash = test_credentials_hash.dup
      test_hash[:cognito] = test_hash[:cognito].dup
      test_hash[:cognito].delete(:logout_uri)
      mock_credentials(test_hash)

      url = described_class.logout_url
      expect(url).to include("logout_uri=http%3A%2F%2Flocalhost%3A3000%2Fauth%2Fcallbacks%2F")
    end

    it "raises MissingCredentialsError when credentials not configured" do
      mock_credentials({})

      expect {
        described_class.logout_url
      }.to raise_error(CognitoService::MissingCredentialsError, "Cognito credentials not configured")
    end
  end

  describe ".decode_id_token" do
    let(:jwks_url) { "https://cognito-idp.sa-east-1.amazonaws.com/sa-east-1_test_pool/.well-known/jwks.json" }

    it "returns empty hash for blank token" do
      expect(described_class.decode_id_token("")).to eq({})
      expect(described_class.decode_id_token(nil)).to eq({})
    end

    it "returns empty hash for invalid token" do
      expect(described_class.decode_id_token("invalid.jwt.token")).to eq({})
    end

    it "returns empty hash when token has no kid in header" do
      # Create a token with header that has no 'kid'
      header = { "alg" => "RS256" }.to_json
      payload = { "sub" => "123" }.to_json
      signature = "fake_signature"
      token = "#{Base64.urlsafe_encode64(header, padding: false)}.#{Base64.urlsafe_encode64(payload, padding: false)}.#{signature}"

      stub_request(:get, jwks_url)
        .to_return(
          status: 200,
          body: { "keys" => [] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      expect(described_class.decode_id_token(token)).to eq({})
    end

    it "returns empty hash when JSON::ParserError occurs" do
      # Token with invalid JSON in header
      invalid_header = "not-valid-json"
      token = "#{Base64.urlsafe_encode64(invalid_header, padding: false)}.payload.signature"

      expect(described_class.decode_id_token(token)).to eq({})
    end

    context "with valid JWT token structure" do
      let(:private_key) { OpenSSL::PKey::RSA.new(2048) }
      let(:public_key) { private_key.public_key }
      let(:jwks_response) do
        # Create JWK from public key
        # Convert RSA modulus and exponent to big-endian byte representation
        # to_s(0) returns the binary representation as a string of bytes
        n_bytes = public_key.n.to_bn.to_s(0)
        e_bytes = public_key.e.to_bn.to_s(0)
        n = Base64.urlsafe_encode64(n_bytes, padding: false)
        e = Base64.urlsafe_encode64(e_bytes, padding: false)
        {
          "keys" => [
            {
              "kid" => "test_kid_123",
              "kty" => "RSA",
              "alg" => "RS256",
              "use" => "sig",
              "n" => n,
              "e" => e
            }
          ]
        }
      end

      before do
        stub_request(:get, jwks_url)
          .to_return(
            status: 200,
            body: jwks_response.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns empty hash when token audience mismatch" do
        payload = {
          "sub" => "user123",
          "aud" => "wrong_client_id",
          "iss" => "https://cognito-idp.sa-east-1.amazonaws.com/sa-east-1_test_pool",
          "exp" => Time.now.to_i + 3600,
          "iat" => Time.now.to_i
        }
        token = JWT.encode(payload, private_key, "RS256", { "kid" => "test_kid_123" })

        result = described_class.decode_id_token(token)
        expect(result).to eq({})
      end

      it "returns empty hash when token issuer mismatch" do
        payload = {
          "sub" => "user123",
          "aud" => "test_client_id",
          "iss" => "https://invalid-issuer.com",
          "exp" => Time.now.to_i + 3600,
          "iat" => Time.now.to_i
        }
        token = JWT.encode(payload, private_key, "RS256", { "kid" => "test_kid_123" })

        result = described_class.decode_id_token(token)
        expect(result).to eq({})
      end

      it "returns empty hash when token is expired" do
        payload = {
          "sub" => "user123",
          "aud" => "test_client_id",
          "iss" => "https://cognito-idp.sa-east-1.amazonaws.com/sa-east-1_test_pool",
          "exp" => Time.now.to_i - 3600, # Expired
          "iat" => Time.now.to_i - 7200
        }
        token = JWT.encode(payload, private_key, "RS256", { "kid" => "test_kid_123" })

        result = described_class.decode_id_token(token)
        expect(result).to eq({})
      end

      it "returns empty hash when kid not found in JWKS" do
        payload = {
          "sub" => "user123",
          "aud" => "test_client_id",
          "iss" => "https://cognito-idp.sa-east-1.amazonaws.com/sa-east-1_test_pool",
          "exp" => Time.now.to_i + 3600,
          "iat" => Time.now.to_i
        }
        token = JWT.encode(payload, private_key, "RS256", { "kid" => "non_existent_kid" })

        result = described_class.decode_id_token(token)
        expect(result).to eq({})
      end

      it "handles JWT::DecodeError gracefully" do
        # Malformed token that will cause decode error
        token = "invalid.token.format"

        expect(described_class.decode_id_token(token)).to eq({})
      end

      it "handles generic exceptions gracefully" do
        # Stub fetch_jwks to raise an exception
        allow(described_class).to receive(:fetch_jwks).and_raise(StandardError.new("Network error"))

        token = "header.payload.signature"
        expect(described_class.decode_id_token(token)).to eq({})
      end
    end
  end

  describe ".exchange_code_for_tokens" do
    let(:token_url) { "https://test-domain.auth.sa-east-1.amazoncognito.com/oauth2/token" }

    context "on success" do
      let(:cognito_response_body) do
        {
          "access_token" => "eyJraWQiOiJcL3BuXC9jY1wvQW1hem9uQ2xvdWRGcm9udEtleSIsImFsZyI6IlJTMjU2In0",
          "id_token" => "eyJraWQiOiJcL3BuXC9jY1wvQW1hem9uQ2xvdWRGcm9udEtleSIsImFsZyI6IlJTMjU2In0",
          "refresh_token" => "eyJjdHkiOiJKV1QiLCJlbmMiOiJBMjU2R0NNIiwiYWxnIjoiUlNBLU9BUCJ9",
          "expires_in" => 3600,
          "token_type" => "Bearer"
        }.to_json
      end

      before do
        stub_request(:post, token_url)
          .to_return(
            status: 200,
            body: cognito_response_body,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns tokens with realistic Cognito response" do
        result = described_class.exchange_code_for_tokens("auth_code_123")

        expect(result["access_token"]).to eq("eyJraWQiOiJcL3BuXC9jY1wvQW1hem9uQ2xvdWRGcm9udEtleSIsImFsZyI6IlJTMjU2In0")
        expect(result["id_token"]).to eq("eyJraWQiOiJcL3BuXC9jY1wvQW1hem9uQ2xvdWRGcm9udEtleSIsImFsZyI6IlJTMjU2In0")
        expect(result["refresh_token"]).to eq("eyJjdHkiOiJKV1QiLCJlbmMiOiJBMjU2R0NNIiwiYWxnIjoiUlNBLU9BUCJ9")
        expect(result["expires_in"]).to eq(3600)
        expect(result["token_type"]).to eq("Bearer")
      end
    end

    context "on invalid_grant error" do
      let(:error_response_body) do
        {
          "error" => "invalid_grant",
          "error_description" => "Authorization code expired"
        }.to_json
      end

      before do
        stub_request(:post, token_url)
          .to_return(
            status: 400,
            body: error_response_body,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns error hash" do
        result = described_class.exchange_code_for_tokens("expired_code")

        expect(result["error"]).to eq("invalid_grant")
        expect(result["error_description"]).to eq("Authorization code expired")
      end
    end

    context "on invalid_client error" do
      let(:error_response_body) do
        {
          "error" => "invalid_client",
          "error_description" => "Client authentication failed"
        }.to_json
      end

      before do
        stub_request(:post, token_url)
          .to_return(
            status: 401,
            body: error_response_body,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns error hash" do
        result = described_class.exchange_code_for_tokens("auth_code_123")

        expect(result["error"]).to eq("invalid_client")
        expect(result["error_description"]).to eq("Client authentication failed")
      end
    end

    context "on network timeout" do
      before do
        stub_request(:post, token_url)
          .to_timeout
      end

      it "raises timeout error" do
        expect {
          described_class.exchange_code_for_tokens("auth_code_123")
        }.to raise_error(Net::OpenTimeout)
      end
    end

    context "on connection error" do
      before do
        stub_request(:post, token_url)
          .to_raise(Errno::ECONNREFUSED.new("Connection refused"))
      end

      it "raises connection error" do
        expect {
          described_class.exchange_code_for_tokens("auth_code_123")
        }.to raise_error(Errno::ECONNREFUSED)
      end
    end
  end

  describe ".get_user_info" do
    let(:userinfo_url) { "https://test-domain.auth.sa-east-1.amazoncognito.com/oauth2/userInfo" }

    context "on success" do
      let(:userinfo_response_body) do
        {
          "sub" => "12345678-1234-1234-1234-123456789012",
          "email_verified" => "true",
          "email" => "test@example.com",
          "name" => "Test User",
          "given_name" => "Test",
          "family_name" => "User",
          "username" => "testuser"
        }.to_json
      end

      before do
        stub_request(:get, userinfo_url)
          .with(headers: { "Authorization" => "Bearer access_token_123" })
          .to_return(
            status: 200,
            body: userinfo_response_body,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns user info with realistic Cognito response" do
        result = described_class.get_user_info("access_token_123")

        expect(result["sub"]).to eq("12345678-1234-1234-1234-123456789012")
        expect(result["email"]).to eq("test@example.com")
        expect(result["email_verified"]).to eq("true")
        expect(result["name"]).to eq("Test User")
        expect(result["given_name"]).to eq("Test")
        expect(result["family_name"]).to eq("User")
        expect(result["username"]).to eq("testuser")
      end
    end

    context "on 401 Unauthorized" do
      before do
        stub_request(:get, userinfo_url)
          .with(headers: { "Authorization" => "Bearer invalid_token" })
          .to_return(
            status: 401,
            body: { "error" => "invalid_token" }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "raises error" do
        expect {
          described_class.get_user_info("invalid_token")
        }.to raise_error(RuntimeError)
      end
    end

    context "on 403 Forbidden" do
      before do
        stub_request(:get, userinfo_url)
          .with(headers: { "Authorization" => "Bearer access_token_123" })
          .to_return(
            status: 403,
            body: { "error" => "insufficient_scope" }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "raises error" do
        expect {
          described_class.get_user_info("access_token_123")
        }.to raise_error(RuntimeError)
      end
    end

    context "on network timeout" do
      before do
        stub_request(:get, userinfo_url)
          .with(headers: { "Authorization" => "Bearer access_token_123" })
          .to_timeout
      end

      it "raises timeout error" do
        expect {
          described_class.get_user_info("access_token_123")
        }.to raise_error(Net::OpenTimeout)
      end
    end

    context "on connection error" do
      before do
        stub_request(:get, userinfo_url)
          .with(headers: { "Authorization" => "Bearer access_token_123" })
          .to_raise(Errno::ECONNREFUSED.new("Connection refused"))
      end

      it "raises connection error" do
        expect {
          described_class.get_user_info("access_token_123")
        }.to raise_error(Errno::ECONNREFUSED)
      end
    end
  end

  describe ".fetch_jwks" do
    let(:jwks_url) { "https://cognito-idp.sa-east-1.amazonaws.com/sa-east-1_test_pool/.well-known/jwks.json" }

    context "on success" do
      let(:jwks_response_body) do
        {
          "keys" => [
            {
              "kid" => "1234example=",
              "alg" => "RS256",
              "kty" => "RSA",
              "e" => "AQAB",
              "n" => "1234567890abcdef",
              "use" => "sig"
            },
            {
              "kid" => "5678example=",
              "alg" => "RS256",
              "kty" => "RSA",
              "e" => "AQAB",
              "n" => "9876543210fedcba",
              "use" => "sig"
            }
          ]
        }.to_json
      end

      before do
        stub_request(:get, jwks_url)
          .to_return(
            status: 200,
            body: jwks_response_body,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns JWKS with realistic Cognito format" do
        result = described_class.send(:fetch_jwks)

        expect(result["keys"].length).to eq(2)
        expect(result["keys"][0]["kid"]).to eq("1234example=")
        expect(result["keys"][0]["alg"]).to eq("RS256")
        expect(result["keys"][0]["kty"]).to eq("RSA")
        expect(result["keys"][0]["e"]).to eq("AQAB")
        expect(result["keys"][0]["use"]).to eq("sig")
      end
    end

    context "on failure" do
      before do
        stub_request(:get, jwks_url)
          .to_return(
            status: 500,
            body: { "error" => "Internal Server Error" }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "raises error" do
        expect {
          described_class.send(:fetch_jwks)
        }.to raise_error(RuntimeError)
      end
    end

    context "caching" do
      let(:jwks_response_body) do
        {
          "keys" => [
            {
              "kid" => "1234example=",
              "alg" => "RS256",
              "kty" => "RSA",
              "e" => "AQAB",
              "n" => "1234567890abcdef",
              "use" => "sig"
            }
          ]
        }.to_json
      end

      before do
        stub_request(:get, jwks_url)
          .to_return(
            status: 200,
            body: jwks_response_body,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "caches JWKS response" do
        # First call should fetch from HTTP
        result1 = described_class.send(:fetch_jwks)
        expect(result1["keys"][0]["kid"]).to eq("1234example=")

        # Second call should return the same result (cached)
        result2 = described_class.send(:fetch_jwks)
        expect(result2).to eq(result1)
        expect(result2["keys"][0]["kid"]).to eq("1234example=")
      end
    end

    context "on network error" do
      before do
        stub_request(:get, jwks_url)
          .to_raise(StandardError.new("Network error"))
      end

      it "raises error and logs" do
        expect(Rails.logger).to receive(:error).at_least(:once)
        expect {
          described_class.send(:fetch_jwks)
        }.to raise_error(StandardError, "Network error")
      end
    end
  end

  describe ".build_public_key_from_jwk" do
    let(:jwks_url) { "https://cognito-idp.sa-east-1.amazonaws.com/sa-east-1_test_pool/.well-known/jwks.json" }
    let(:private_key) { OpenSSL::PKey::RSA.new(2048) }
    let(:public_key) { private_key.public_key }
    let(:jwks_response) do
      # Create JWK from public key
      # Convert RSA modulus and exponent to big-endian byte representation
      # to_s(0) returns the binary representation as a string of bytes
      n_bytes = public_key.n.to_bn.to_s(0)
      e_bytes = public_key.e.to_bn.to_s(0)
      n = Base64.urlsafe_encode64(n_bytes, padding: false)
      e = Base64.urlsafe_encode64(e_bytes, padding: false)
      {
        "keys" => [
          {
            "kid" => "test_kid_123",
            "kty" => "RSA",
            "alg" => "RS256",
            "use" => "sig",
            "n" => n,
            "e" => e
          }
        ]
      }
    end

    before do
      stub_request(:get, jwks_url)
        .to_return(
          status: 200,
          body: jwks_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "builds public key from JWK successfully when used in decode_id_token flow" do
      # Test through decode_id_token which internally uses build_public_key_from_jwk
      # This tests the full flow including build_public_key_from_jwk (uses legacy method on OpenSSL 3.0+)
      payload = {
        "sub" => "user123",
        "aud" => "test_client_id",
        "iss" => "https://cognito-idp.sa-east-1.amazonaws.com/sa-east-1_test_pool",
        "exp" => Time.now.to_i + 3600,
        "iat" => Time.now.to_i
      }
      token = JWT.encode(payload, private_key, "RS256", { "kid" => "test_kid_123" })

      result = described_class.decode_id_token(token)
      # The build_public_key_from_jwk is tested indirectly through successful token decode
      # build_rsa_key_from_components will use legacy method on OpenSSL 3.0+
      expect(result).not_to be_empty
      expect(result["sub"]).to eq("user123")
      expect(result["aud"]).to eq("test_client_id")
    end

    it "handles errors gracefully and logs" do
      invalid_jwk = { "n" => "invalid", "e" => "invalid" }
      expect(Rails.logger).to receive(:error).at_least(:once)
      expect {
        described_class.send(:build_public_key_from_jwk, invalid_jwk)
      }.to raise_error(StandardError)
    end
  end

  describe "private helper methods" do
    describe ".validate_token_audience" do
      it "returns true when audience matches" do
        payload = { "aud" => "test_client_id" }
        expect(described_class.send(:validate_token_audience, payload)).to be true
      end

      it "returns true when audience is array and includes client_id" do
        payload = { "aud" => [ "test_client_id", "other_client" ] }
        expect(described_class.send(:validate_token_audience, payload)).to be true
      end

      it "returns false when audience mismatch" do
        payload = { "aud" => "wrong_client_id" }
        expect(Rails.logger).to receive(:error)
        expect(described_class.send(:validate_token_audience, payload)).to be false
      end

      it "returns false when audience array doesn't include client_id" do
        payload = { "aud" => [ "other_client" ] }
        expect(Rails.logger).to receive(:error)
        expect(described_class.send(:validate_token_audience, payload)).to be false
      end
    end

    describe ".validate_token_issuer" do
      it "returns true when issuer matches Cognito pattern (cognito-idp)" do
        payload = { "iss" => "https://cognito-idp.sa-east-1.amazonaws.com/sa-east-1_test_pool" }
        expect(described_class.send(:validate_token_issuer, payload)).to be true
      end

      it "returns true when issuer matches Cognito pattern (auth domain)" do
        payload = { "iss" => "https://test-domain.auth.sa-east-1.amazoncognito.com" }
        expect(described_class.send(:validate_token_issuer, payload)).to be true
      end

      it "returns false when issuer doesn't match pattern" do
        payload = { "iss" => "https://invalid-issuer.com" }
        expect(Rails.logger).to receive(:error)
        expect(described_class.send(:validate_token_issuer, payload)).to be false
      end

      it "returns false when issuer is nil" do
        payload = { "iss" => nil }
        expect(Rails.logger).to receive(:error)
        expect(described_class.send(:validate_token_issuer, payload)).to be false
      end
    end

    describe ".build_issuer_pattern" do
      it "builds correct regex pattern for region" do
        pattern = described_class.send(:build_issuer_pattern)
        expect(pattern).to be_a(Regexp)
        expect("https://cognito-idp.sa-east-1.amazonaws.com/pool").to match(pattern)
        expect("https://domain.auth.sa-east-1.amazoncognito.com").to match(pattern)
        expect("https://invalid.com").not_to match(pattern)
      end
    end
  end
end
