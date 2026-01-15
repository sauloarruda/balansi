module Auth
  class SignUpInteraction < ActiveInteraction::Base
    string :code
    string :state, default: nil
    string :timezone, default: nil
    string :language, default: nil

    validates :code, presence: true

    # Exchange authorization code for tokens, create or find user, and create patient record
    #
    # @param code [String] Authorization code from Cognito OAuth callback (required)
    # @param state [String, nil] Optional state parameter containing business data (e.g., professional_id)
    # @param timezone [String, nil] IANA timezone identifier (e.g., "America/Sao_Paulo")
    #   Defaults to "America/Sao_Paulo" if not provided
    # @param language [String, nil] Language code (e.g., "pt", "en")
    #   Defaults to "pt" if not provided
    # @return [Hash, nil] On success, returns hash with keys:
    #   - :user [User] The created or found user record
    #   - :refresh_token [String] Refresh token from Cognito
    #   On failure, returns nil and errors are available via {ActiveInteraction::Base#errors}
    # @raise [ActiveInteraction::InvalidInteractionError] If code parameter is missing
    #
    # @example Successful authentication
    #   result = Auth::SignUpInteraction.run(code: "abc123", state: "professional_id=456")
    #   if result.valid?
    #     user = result.result[:user]
    #     refresh_token = result.result[:refresh_token]
    #   else
    #     errors = result.errors.full_messages
    #   end
    #
    # @note This interaction:
    #   - Exchanges authorization code for tokens from Cognito
    #   - Verifies ID token signature using Cognito JWKS
    #   - Creates or finds user by Cognito ID (sub claim)
    #   - Creates patient record with professional_id from state parameter
    #   - Sets user timezone and language only on initial creation
    def execute
      # Exchange code for tokens (handles errors internally)
      tokens = exchange_code_for_tokens
      return nil unless tokens

      # Extract and validate tokens
      access_token = tokens["access_token"]
      id_token = tokens["id_token"]
      refresh_token = tokens["refresh_token"]

      return nil unless validate_tokens(access_token, id_token, refresh_token)

      # Retrieve user information from Cognito (ID token preferred, userinfo as fallback)
      user_info = retrieve_user_info(id_token, access_token)

      # Validate user information is complete
      return nil unless user_info_valid?(user_info)

      # Detect timezone and language from browser (defaults for new users)
      detected_timezone = timezone || "America/Sao_Paulo"
      detected_language = language || "pt"

      # Find or create user (adds errors to errors object on failure)
      user = find_or_create_user(user_info, detected_timezone, detected_language)
      return nil unless user

      # Create patient record (required - authentication fails if this fails)
      return nil unless create_patient_record(user)

      # Return result hash with user and refresh_token
      { user: user, refresh_token: refresh_token }
    end

    private

    # Exchange authorization code for tokens from Cognito
    # Returns tokens hash on success, nil on failure (errors added to errors object)
    def exchange_code_for_tokens
      tokens = CognitoService.exchange_code_for_tokens(code)

      return tokens unless tokens["error"]

      # Handle token exchange errors with appropriate error messages
      error_code = tokens["error"]
      error_description = tokens["error_description"].presence || error_code

      if error_code == "invalid_grant"
        errors.add(:base, "The authorization code has already been used or has expired. Please try signing in again.")
      else
        errors.add(:base, "Token exchange failed: #{error_code} - #{error_description}")
      end

      nil
    end

    # Validate that all required tokens are present
    # Returns true if all tokens present, false otherwise (adds errors)
    def validate_tokens(access_token, id_token, refresh_token)
      return true if access_token && id_token && refresh_token

      missing_tokens = []
      missing_tokens << "access_token" unless access_token
      missing_tokens << "id_token" unless id_token
      missing_tokens << "refresh_token" unless refresh_token

      errors.add(:base, "Missing required tokens from Cognito response: #{missing_tokens.join(", ")}")
      false
    end

    # Retrieve user information from Cognito (ID token preferred, userinfo as fallback)
    # Returns hash with sub, email, and name keys
    def retrieve_user_info(id_token, access_token)
      # Try ID token first (contains all necessary claims)
      user_info = {}
      if id_token.present?
        decoded_token = CognitoService.decode_id_token(id_token)
        user_info = {
          "sub" => decoded_token["sub"],
          "email" => decoded_token["email"],
          "name" => decoded_token["name"] || decoded_token["given_name"] || decoded_token["email"]
        }
      end

      # Fallback to userinfo endpoint if ID token didn't work
      if user_info["sub"].blank? && access_token.present?
        begin
          userinfo_response = CognitoService.get_user_info(access_token)
          user_info.merge!(userinfo_response)
        rescue => e
          Rails.logger.warn("Failed to get user info from userinfo endpoint: #{e.class}: #{e.message}")
        end
      end

      user_info
    end

    # Validate that user_info contains required fields (sub and email)
    # Returns true if valid, false otherwise (adds errors to errors object)
    def user_info_valid?(user_info)
      if user_info["sub"].blank?
        errors.add(:base, "Unable to retrieve user identifier (sub) from Cognito. ID token and userinfo endpoint both failed.")
        return false
      end

      return true unless user_info["email"].blank?

      errors.add(:base, "Unable to retrieve email from Cognito. User ID: #{user_info["sub"]}")
      false
    end

    # Create patient record for user (required - authentication fails if this fails)
    # Returns true on success, false on failure (errors added to errors object)
    def create_patient_record(user)
      professional_id = parse_professional_id

      unless professional_id.present?
        errors.add(:base, "Missing professional identification")
        return false
      end

      Patient.find_or_create_by!(
        user_id: user.id,
        professional_id: professional_id
      )

      true
    rescue ActiveRecord::RecordInvalid => e
      errors.add(:base, "Failed to create patient record: #{e.record.errors.full_messages.join(", ")}")
      Rails.logger.error("Patient creation failed: #{e.class}: #{e.message}. Record errors: #{e.record.errors.full_messages.inspect}")
      false
    rescue ActiveRecord::RecordNotUnique => e
      errors.add(:base, "Patient record already exists for this user and professional")
      Rails.logger.error("Patient record uniqueness violation: #{e.class}: #{e.message}")
      false
    rescue => e
      errors.add(:base, "Failed to create patient record: #{e.class}: #{e.message}")
      Rails.logger.error("Patient creation exception: #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.first(10).join("\n"))
      false
    end

    # Find or create user in database based on Cognito user info
    # Returns User instance on success, nil on failure (errors added to errors object)
    def find_or_create_user(user_info, detected_timezone, detected_language)
      cognito_id = user_info["sub"]

      if cognito_id.blank?
        errors.add(:base, "Cognito user ID (sub) is missing. User info received: #{user_info.inspect}")
        return nil
      end

      begin
        user = User.find_or_initialize_by(cognito_id: cognito_id)
        setup_new_user(user, user_info, detected_timezone, detected_language) if user.new_record?
        user
      rescue ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished, StandardError => e
        handle_user_creation_error(e)
        nil
      end
    end

    def setup_new_user(user, user_info, detected_timezone, detected_language)
      user.name = user_info["name"] || user_info["email"] || "User"
      user.email = user_info["email"]
      user.timezone = detected_timezone
      user.language = detected_language

      return if user.save

      errors.add(:base, "Failed to save user: #{user.errors.full_messages.join(", ")}")
      Rails.logger.error("User creation failed. Attributes: #{user.attributes.inspect}, Errors: #{user.errors.full_messages.inspect}")
      nil
    end

    def handle_user_creation_error(error)
      errors.add(:base, "Failed to create or find user: #{error.class}: #{error.message}")
      Rails.logger.error("User creation exception: #{error.class}: #{error.message}")
      Rails.logger.error(error.backtrace.first(10).join("\n"))
    end

    # Parse professional_id from state parameter
    # Returns professional_id string or nil if not present or invalid
    def parse_professional_id
      return nil if state.blank?

      state_params = URI.decode_www_form(state).to_h
      state_params["professional_id"]
    rescue ArgumentError, URI::InvalidURIError => e
      Rails.logger.warn("Failed to parse professional_id from state parameter: #{e.class}: #{e.message}")
      nil
    end
  end
end
