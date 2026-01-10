class CognitoService
  # Use Rails credentials instead of environment variables
  # Load credentials lazily to handle cases where they're not yet configured

  # Get credentials for the current environment
  def self.credentials
    Rails.application.credentials(Rails.env.to_sym)
  rescue ArgumentError
    # Fallback to default credentials if environment-specific doesn't exist
    Rails.application.credentials
  end

  # Exchange authorization code for access token, ID token, and refresh token
  #
  # @param code [String] Authorization code received from Cognito OAuth callback
  # @return [Hash] Response hash with keys:
  #   - "access_token" [String] OAuth access token
  #   - "id_token" [String] JWT ID token containing user claims
  #   - "refresh_token" [String] Refresh token for obtaining new access tokens
  #   - "token_type" [String] Token type (typically "Bearer")
  #   - "expires_in" [Integer] Access token expiration time in seconds
  #   On error, returns hash with:
  #   - "error" [String] Error code (e.g., "invalid_grant", "invalid_client")
  #   - "error_description" [String] Human-readable error description
  #
  # @example Successful token exchange
  #   tokens = CognitoService.exchange_code_for_tokens("auth_code_123")
  #   if tokens["error"]
  #     puts "Error: #{tokens['error_description']}"
  #   else
  #     access_token = tokens["access_token"]
  #   end
  #
  # @note Uses client_secret for authentication (confidential client flow)
  def self.exchange_code_for_tokens(code)
    redirect_uri = cognito_credentials[:redirect_uri]
    client_id = cognito_credentials[:client_id]
    token_url_value = token_url

    log_token_exchange_request(token_url_value, redirect_uri, client_id, code)

    request_body = build_token_request_body(code, client_id, redirect_uri)
    response = HTTParty.post(token_url_value, body: request_body)
    parsed_response = JSON.parse(response.body)

    log_token_exchange_response(response, parsed_response, token_url_value, redirect_uri, client_id, code)

    parsed_response
  end

  # Retrieve user information from Cognito userinfo endpoint
  #
  # @param access_token [String] Valid OAuth access token
  # @return [Hash] User information hash with keys:
  #   - "sub" [String] Cognito user ID (subject)
  #   - "email" [String] User email address
  #   - "name" [String] User full name (if available)
  #   - Other claims as configured in Cognito User Pool
  # @raise [RuntimeError] If the request fails (non-2xx response)
  #
  # @note This is a fallback method. Prefer using {#decode_id_token} which extracts
  #   user info from the ID token JWT, as it's more efficient and doesn't require
  #   an additional HTTP request.
  def self.get_user_info(access_token)
    response = HTTParty.get(userinfo_url, headers: {
      "Authorization" => "Bearer #{access_token}"
    })

    if response.success?
      JSON.parse(response.body)
    else
      Rails.logger.error("Failed to get user info: #{response.code} - #{response.body}")
      raise "Failed to retrieve user information from Cognito: #{response.code}"
    end
  end

  # Decode and verify ID token (JWT) using Cognito's public keys
  #
  # Verifies JWT signature using JWKS (JSON Web Key Set) from Cognito.
  # Validates token expiration, issued-at time, audience, and issuer.
  #
  # @param id_token [String] JWT ID token from Cognito
  # @return [Hash] Decoded token payload with user claims:
  #   - "sub" [String] Cognito user ID (subject)
  #   - "email" [String] User email address
  #   - "name" [String] User full name (if available)
  #   - "exp" [Integer] Token expiration timestamp
  #   - "iat" [Integer] Token issued-at timestamp
  #   - "aud" [String, Array] Token audience (client_id)
  #   - "iss" [String] Token issuer (Cognito User Pool URL)
  #   Returns empty hash {} if token is invalid, expired, or verification fails
  #
  # @example Decode and verify ID token
  #   payload = CognitoService.decode_id_token(id_token)
  #   if payload["sub"].present?
  #     user_id = payload["sub"]
  #     email = payload["email"]
  #   end
  #
  # @note This method:
  #   - Fetches JWKS from Cognito (cached for 1 hour)
  #   - Verifies JWT signature using RS256 algorithm
  #   - Validates token expiration and issued-at claims
  #   - Validates audience matches client_id
  #   - Validates issuer matches Cognito domain pattern
  #   - Handles all errors gracefully and returns empty hash on failure
  def self.decode_id_token(id_token)
    return {} if id_token.blank?

    decoded_payload = verify_id_token(id_token)
    return {} unless decoded_payload

    return {} unless validate_token_claims(decoded_payload)

    decoded_payload
  rescue JWT::DecodeError, JWT::VerificationError, JWT::ExpiredSignature, JWT::InvalidIatError => e
    Rails.logger.error("JWT verification failed: #{e.class}: #{e.message}")
    {}
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse JWT header: #{e.message}")
    {}
  rescue => e
    Rails.logger.error("Failed to decode ID token: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n"))
    {}
  end

  def self.verify_id_token(id_token)
    kid = extract_kid_from_token(id_token)
    return nil unless kid

    jwk = find_jwk_for_kid(kid)
    return nil unless jwk

    public_key = build_public_key_from_jwk(jwk)
    verify_and_decode_jwt(id_token, public_key)
  end

  def self.validate_token_claims(decoded_payload)
    validate_token_audience(decoded_payload) && validate_token_issuer(decoded_payload)
  end

  def self.extract_kid_from_token(id_token)
    header_part = id_token.split(".")[0]
    remainder = header_part.length % 4
    header_part += "=" * (4 - remainder) if remainder != 0
    header = JSON.parse(Base64.urlsafe_decode64(header_part))
    kid = header["kid"]

    return kid if kid

    Rails.logger.error("No 'kid' found in JWT header")
    nil
  end

  def self.find_jwk_for_kid(kid)
    jwks = fetch_jwks
    jwk = jwks["keys"].find { |key| key["kid"] == kid }

    return jwk if jwk

    Rails.logger.error("No matching key found in JWKS for kid: #{kid}")
    nil
  end

  def self.verify_and_decode_jwt(id_token, public_key)
    decoded_payload, = JWT.decode(
      id_token,
      public_key,
      true,
      {
        algorithm: "RS256",
        verify_iat: true,
        verify_expiration: true
      }
    )
    decoded_payload
  end

  def self.validate_token_audience(decoded_payload)
    token_aud = decoded_payload["aud"]
    expected_aud = cognito_credentials[:client_id]

    aud_matches = if token_aud.is_a?(Array)
      token_aud.include?(expected_aud)
    else
      token_aud == expected_aud
    end

    return true if aud_matches

    Rails.logger.error("Token audience mismatch. Expected: #{expected_aud}, Got: #{token_aud.inspect}")
    false
  end

  def self.validate_token_issuer(decoded_payload)
    issuer = decoded_payload["iss"]
    expected_issuer_pattern = build_issuer_pattern

    return true if issuer&.match?(expected_issuer_pattern)

    Rails.logger.error("Token issuer mismatch. Expected Cognito issuer pattern, Got: #{issuer}")
    false
  end

  def self.build_issuer_pattern
    region = Regexp.escape(cognito_credentials[:region])
    /^https:\/\/(cognito-idp\.#{region}\.amazonaws\.com\/[^\/]+|[^\/]+\.auth\.#{region}\.amazoncognito\.com)/
  end

  # Generate Cognito login URL for OAuth authorization flow
  #
  # @param state [String, nil] Optional state parameter for CSRF protection and
  #   passing business data (e.g., professional_id). Should be URL-encoded.
  # @param locale [Symbol] Browser locale (:pt or :en). Note: Managed Login V2
  #   uses Accept-Language header instead of query parameter.
  # @return [String] Full Cognito OAuth authorization URL
  # @raise [MissingCredentialsError] If Cognito credentials are not configured
  #
  # @example Generate login URL with state parameter
  #   state = URI.encode_www_form(csrf_token: token, professional_id: "123")
  #   url = CognitoService.login_url(state: state)
  #   redirect_to url, allow_other_host: true
  #
  # @note Uses Managed Login V2 endpoint (/oauth2/authorize) which automatically
  #   redirects to the login page. Language is determined by Accept-Language header.
  def self.login_url(state: nil, locale: :pt)
    raise MissingCredentialsError, "Cognito credentials not configured" unless credentials_configured?
    # Note: Managed Login V2 uses /oauth2/authorize which redirects to /login
    # The lang parameter is set via Accept-Language header or browser settings
    # Managed Login V2 doesn't support lang query parameter directly
    params = {
      client_id: cognito_credentials[:client_id],
      response_type: "code",
      redirect_uri: cognito_credentials[:redirect_uri],
      scope: "openid email profile"
    }
    params[:state] = state if state
    # Use /oauth2/authorize - Managed Login V2 will handle the redirect to /login internally
    "#{base_url}/oauth2/authorize?#{params.to_query}"
  end

  # Generate Cognito signup URL for OAuth authorization flow
  #
  # @param state [String, nil] Optional state parameter for CSRF protection and
  #   passing business data (e.g., professional_id). Should be URL-encoded.
  # @param locale [Symbol] Browser locale (:pt or :en). Note: Managed Login V2
  #   uses Accept-Language header instead of query parameter.
  # @return [String] Full Cognito OAuth authorization URL
  # @raise [MissingCredentialsError] If Cognito credentials are not configured
  #
  # @example Generate signup URL
  #   state = URI.encode_www_form(csrf_token: token)
  #   url = CognitoService.signup_url(state: state)
  #   redirect_to url, allow_other_host: true
  #
  # @note Uses Managed Login V2 endpoint (/oauth2/authorize) which automatically
  #   redirects to the signup page. Language is determined by Accept-Language header.
  def self.signup_url(state: nil, locale: :pt)
    raise MissingCredentialsError, "Cognito credentials not configured" unless credentials_configured?
    # Note: Managed Login V2 uses /oauth2/authorize which redirects to /signup
    # The lang parameter is set via Accept-Language header or browser settings
    # Managed Login V2 doesn't support lang query parameter directly
    params = {
      client_id: cognito_credentials[:client_id],
      response_type: "code",
      redirect_uri: cognito_credentials[:redirect_uri],
      scope: "openid email profile"
    }
    params[:state] = state if state
    # Use /oauth2/authorize with identity_provider parameter or let Cognito show signup option
    # Managed Login V2 will redirect to appropriate page (/signup)
    "#{base_url}/oauth2/authorize?#{params.to_query}"
  end

  # Generate Cognito logout URL to invalidate user session
  #
  # @param logout_uri_param [String, nil] Optional logout redirect URI.
  #   If not provided, uses logout_uri from credentials, or falls back to redirect_uri.
  #   Must match exactly one of the "Sign out URL(s)" configured in Cognito User Pool Client.
  # @return [String] Full Cognito logout URL
  # @raise [MissingCredentialsError] If Cognito credentials are not configured
  #
  # @example Generate logout URL
  #   url = CognitoService.logout_url
  #   redirect_to url, allow_other_host: true, status: :see_other
  #
  # @note The logout_uri must match exactly what's configured in Terraform (logout_urls).
  #   Normalizes logout_uri to ensure trailing slash for consistency.
  #   Works with both Managed Login V1 and V2.
  def self.logout_url(logout_uri_param: nil)
    raise MissingCredentialsError, "Cognito credentials not configured" unless credentials_configured?
    # Use provided logout_uri, or from credentials, or fallback to redirect_uri
    # Ensure logout_uri matches exactly what's configured in Terraform (logout_urls)
    # In dev: "http://localhost:3000/" (with trailing slash)
    logout_uri_param ||= cognito_credentials[:logout_uri] || cognito_credentials[:redirect_uri]

    # Normalize logout_uri to ensure it matches the configured sign-out URL
    # Add trailing slash if missing (to match Terraform config: http://localhost:3000/)
    logout_uri_param = logout_uri_param.chomp("/") + "/" unless logout_uri_param.end_with?("/")

    # Cognito logout endpoint (works with both Managed Login V1 and V2)
    # Format: https://{domain}.auth.{region}.amazoncognito.com/logout?client_id={client_id}&logout_uri={logout_uri}
    # Note: logout_uri must match exactly one of the "Sign out URL(s)" in User Pool Client settings
    # The endpoint only accepts GET requests
    params = {
      client_id: cognito_credentials[:client_id],
      logout_uri: logout_uri_param
    }
    "#{base_url}/logout?#{params.to_query}"
  end

  # Convert browser language locale to Cognito language code
  # Returns "pt-BR" or "en", defaults to "pt-BR"
  # @param locale [Symbol] Browser locale (:pt or :en)
  # @return [String] Cognito language code ("pt-BR" or "en")
  def self.cognito_language_code(locale)
    case locale
    when :pt
      "pt-BR"
    when :en
      "en"
    else
      "pt-BR"
    end
  end

  private

  def self.cognito_credentials
    credentials.dig(:cognito) || {}
  end

  def self.credentials_configured?
    cognito_credentials.present?
  end

  def self.base_url
    "https://#{cognito_credentials[:domain]}.auth.#{cognito_credentials[:region]}.amazoncognito.com"
  end

  def self.token_url
    "#{base_url}/oauth2/token"
  end

  def self.userinfo_url
    "#{base_url}/oauth2/userInfo"
  end

  def self.jwks_url
    # JWKS endpoint for Cognito User Pool
    # Format: https://cognito-idp.{region}.amazonaws.com/{userPoolId}/.well-known/jwks.json
    user_pool_id = cognito_credentials[:user_pool_id]
    region = cognito_credentials[:region]
    "https://cognito-idp.#{region}.amazonaws.com/#{user_pool_id}/.well-known/jwks.json"
  end

  # Fetch JWKS (JSON Web Key Set) from Cognito with caching
  # Cache JWKS for 1 hour to avoid fetching on every token verification
  def self.fetch_jwks
    Rails.cache.fetch("cognito_jwks", expires_in: 1.hour) do
      response = HTTParty.get(jwks_url)

      unless response.success?
        Rails.logger.error("Failed to fetch JWKS: #{response.code} - #{response.body}")
        raise "Failed to retrieve JWKS from Cognito: #{response.code}"
      end

      JSON.parse(response.body)
    end
  rescue => e
    Rails.logger.error("Failed to fetch JWKS: #{e.class}: #{e.message}")
    raise
  end

  # Build OpenSSL::PKey::RSA public key from JWK (JSON Web Key)
  # JWK format: { "kty": "RSA", "kid": "...", "n": "...", "e": "..." }
  def self.build_public_key_from_jwk(jwk)
    require "openssl"

    modulus, exponent = extract_jwk_components(jwk)
    n_bn, e_bn = convert_to_big_numbers(modulus, exponent)

    build_rsa_key_from_components(n_bn, e_bn)
  rescue => e
    Rails.logger.error("Failed to build public key from JWK: #{e.class}: #{e.message}")
    Rails.logger.error("JWK n length: #{jwk["n"]&.length}, e length: #{jwk["e"]&.length}")
    raise
  end

  def self.extract_jwk_components(jwk)
    modulus = Base64.urlsafe_decode64(jwk["n"])
    exponent = Base64.urlsafe_decode64(jwk["e"])
    [ modulus, exponent ]
  end

  def self.convert_to_big_numbers(modulus, exponent)
    n_bn = OpenSSL::BN.new(modulus, 2)
    e_bn = OpenSSL::BN.new(exponent, 2)
    [ n_bn, e_bn ]
  end

  def self.build_rsa_key_from_components(n_bn, e_bn)
    rsa_key = OpenSSL::PKey::RSA.new

    return build_modern_rsa_key(rsa_key, n_bn, e_bn) if rsa_key.respond_to?(:set_key)

    build_legacy_rsa_key(n_bn, e_bn)
  end

  def self.build_modern_rsa_key(rsa_key, n_bn, e_bn)
    rsa_key.set_key(n_bn, e_bn, nil)
    rsa_key
  end

  def self.build_legacy_rsa_key(n_bn, e_bn)
    sequence = OpenSSL::ASN1::Sequence.new([
      OpenSSL::ASN1::Integer.new(n_bn),
      OpenSSL::ASN1::Integer.new(e_bn)
    ])

    algorithm = OpenSSL::ASN1::Sequence.new([
      OpenSSL::ASN1::ObjectId.new("rsaEncryption"),
      OpenSSL::ASN1::Null.new(nil)
    ])

    public_key_info = OpenSSL::ASN1::Sequence.new([
      algorithm,
      OpenSSL::ASN1::BitString.new(sequence.to_der)
    ])

    OpenSSL::PKey::RSA.new(public_key_info.to_der)
  end

  class MissingCredentialsError < StandardError; end

  def self.log_token_exchange_request(token_url_value, redirect_uri, client_id, code)
    Rails.logger.info("=== TOKEN EXCHANGE REQUEST ===")
    Rails.logger.info("Token URL: #{token_url_value}")
    Rails.logger.info("redirect_uri: #{redirect_uri}")
    Rails.logger.info("client_id: #{client_id}")
    Rails.logger.info("code: #{code}")
    Rails.logger.info("code length: #{code&.length}")
  end

  def self.build_token_request_body(code, client_id, redirect_uri)
    request_body = {
      grant_type: "authorization_code",
      code: code,
      client_id: client_id,
      client_secret: cognito_credentials[:client_secret],
      redirect_uri: redirect_uri
    }
    Rails.logger.info("Request body keys: #{request_body.keys.inspect}")
    request_body
  end

  def self.log_token_exchange_response(response, parsed_response, token_url_value, redirect_uri, client_id, code)
    Rails.logger.info("Response status: #{response.code}")
    Rails.logger.info("Response body keys: #{parsed_response.keys.inspect}")

    if response.success?
      log_successful_token_exchange(parsed_response)
    else
      log_failed_token_exchange(response, parsed_response, token_url_value, redirect_uri, client_id, code)
    end
  end

  def self.log_successful_token_exchange(parsed_response)
    Rails.logger.info("=== TOKEN EXCHANGE SUCCESS ===")
    Rails.logger.info("Access token present: #{parsed_response["access_token"].present?}")
    Rails.logger.info("ID token present: #{parsed_response["id_token"].present?}")
    Rails.logger.info("Refresh token present: #{parsed_response["refresh_token"].present?}")
  end

  def self.log_failed_token_exchange(response, parsed_response, token_url_value, redirect_uri, client_id, code)
    log_failure_details(response, parsed_response, token_url_value, redirect_uri, client_id, code)

    return unless parsed_response["error"] == "invalid_grant"

    log_invalid_grant_diagnosis(redirect_uri, client_id, code)
  end

  def self.log_failure_details(response, parsed_response, token_url_value, redirect_uri, client_id, code)
    Rails.logger.error("=== TOKEN EXCHANGE FAILED ===")
    Rails.logger.error("Status: #{response.code}")
    Rails.logger.error("Response: #{parsed_response.inspect}")
    Rails.logger.error("Token URL: #{token_url_value}")
    log_request_params(redirect_uri, client_id, code)
  end

  def self.log_request_params(redirect_uri, client_id, code)
    Rails.logger.error("Request params:")
    Rails.logger.error("  - redirect_uri: #{redirect_uri}")
    Rails.logger.error("  - client_id: #{client_id}")
    Rails.logger.error("  - code: #{code}")
  end

  def self.log_invalid_grant_diagnosis(redirect_uri, client_id, code)
    Rails.logger.error("=== INVALID_GRANT DIAGNOSIS ===")
    log_invalid_grant_causes(redirect_uri, client_id, code)
  end

  def self.log_invalid_grant_causes(redirect_uri, client_id, code)
    Rails.logger.error("Possible causes:")
    Rails.logger.error("  1. Authorization code already used (codes can only be used once)")
    Rails.logger.error("  2. Authorization code expired (codes expire in 1-2 minutes)")
    log_uri_and_client_mismatch(redirect_uri, client_id, code)
  end

  def self.log_uri_and_client_mismatch(redirect_uri, client_id, code)
    Rails.logger.error("  3. redirect_uri mismatch - must match exactly what was used in /oauth2/authorize")
    Rails.logger.error("     - Expected (from credentials): #{redirect_uri}")
    Rails.logger.error("     - Used in login URL: #{redirect_uri}")
    Rails.logger.error("  4. client_id mismatch")
    Rails.logger.error("     - Used: #{client_id}")
    Rails.logger.error("  5. client_secret incorrect or missing")
    Rails.logger.error("  6. Code may have been used in a previous request (check cache for: auth_code_processed:#{code})")
  end
end
