class Auth::CallbacksController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :ensure_current_patient!
  before_action :validate_csrf_protection, :check_code_idempotency

  # Handles OAuth callback from AWS Cognito
  #
  # Expected parameters:
  #   - code: Authorization code from Cognito (required)
  #   - state: State parameter containing CSRF token and optional business params (required)
  #
  # Side effects:
  #   - Creates or updates user record
  #   - Creates patient record
  #   - Establishes session
  #   - Marks authorization code as processed
  #
  # Renders:
  #   - Redirects to root_path on success
  #   - Renders error view on failure
  def show
    validated_state = extract_validated_state(params[:state])
    result = run_sign_up_interaction(validated_state)

    mark_code_as_processed(result)

    handle_authentication_result(result)
  rescue => e
    handle_authentication_exception(e)
  end

  private

  def code_hash_for_logging
    return "nil" if params[:code].blank?

    Digest::SHA256.hexdigest(params[:code])[0..8]
  end

  def validate_csrf_protection
    return if validate_state_parameter(params[:state])

    Rails.logger.error("Invalid state parameter - possible CSRF attack. Expected: #{session[:oauth_state].inspect}, Received: #{params[:state]}")
    error_message = format_error_message("Invalid authentication request")
    render :error, status: :forbidden, locals: { error_message: error_message }
  end

  def check_code_idempotency
    authorization_code_key = authorization_code_cache_key
    return unless Rails.cache.exist?(authorization_code_key)

    Rails.logger.error("Authorization code already processed (idempotency check): #{code_hash_for_logging}...")
    error_message = format_error_message("This authentication request has already been processed. Please try signing in again.")
    render :error, status: :bad_request, locals: { error_message: error_message }
  end

  def authorization_code_cache_key
    "auth_code_processed:#{params[:code]}"
  end

  CODE_CACHE_EXPIRATION = 5.minutes.freeze

  def run_sign_up_interaction(validated_state)
    Auth::SignUpInteraction.run(
      code: params[:code],
      state: validated_state,
      timezone: detect_browser_timezone,
      language: detect_browser_language.to_s
    )
  end

  def mark_code_as_processed_with_reason(reason: nil)
    authorization_code_key = authorization_code_cache_key
    Rails.cache.write(authorization_code_key, true, expires_in: CODE_CACHE_EXPIRATION)

    log_message = "Authorization code marked as processed: #{code_hash_for_logging}..."
    log_message += " (reason: #{reason})" if reason
    Rails.logger.info(log_message)
  end

  def mark_code_as_processed(result)
    token_exchange_error = find_token_exchange_error(result)

    return unless result.valid? || token_exchange_error

    reason = result.valid? ? "success" : "invalid_grant"
    mark_code_as_processed_with_reason(reason: reason)
  end

  def find_token_exchange_error(result)
    result.errors.full_messages.find do |msg|
      msg.include?("Token exchange failed") && msg.include?("invalid_grant")
    end
  end

  def handle_authentication_result(result)
    return handle_failed_authentication(result) unless result.valid? && result.result.present?

    handle_successful_authentication(result.result)
  end

  def handle_successful_authentication(result_hash)
    return unless valid_result_hash?(result_hash)

    user = result_hash[:user]
    refresh_token = result_hash[:refresh_token]

    save_session(user, refresh_token)
    redirect_to root_path
  end

  def valid_result_hash?(result_hash)
    return true if result_hash.is_a?(Hash) && result_hash[:user] && result_hash[:refresh_token]

    Rails.logger.error("Invalid result hash: #{result_hash.inspect}")
    error_message = format_error_message("Invalid response from authentication service")
    render :error, status: :unprocessable_entity, locals: { error_message: error_message }
    false
  end

  def save_session(user, refresh_token)
    reset_session # Regenerates session ID and clears old session data to prevent session fixation
    flash.clear
    session[:user_id] = user.id
    session[:refresh_token] = refresh_token
  end

  def handle_failed_authentication(result)
    error_details = result.errors.full_messages.join(", ")
    Rails.logger.error("Auth callback error: #{error_details}")

    mark_code_for_invalid_grant(error_details)

    error_message = format_error_message(error_details.presence || "Authentication failed")
    render :error, status: :unprocessable_entity, locals: { error_message: error_message }
  end

  def mark_code_for_invalid_grant(error_details)
    return unless error_details.include?("invalid_grant")

    mark_code_as_processed_with_reason(reason: "invalid_grant")
  end

  def handle_authentication_exception(exception)
    Rails.logger.error("Auth callback exception: #{exception.class}: #{exception.message}")
    Rails.logger.error(exception.backtrace.first(10).join("\n"))

    mark_code_for_exception(exception)

    error_message = format_error_message("Authentication failed", exception: exception)
    render :error, status: :internal_server_error, locals: { error_message: error_message }
  end

  def mark_code_for_exception(exception)
    return unless exception.message.to_s.include?("invalid_grant") || exception.message.to_s.include?("Token exchange")

    mark_code_as_processed_with_reason(reason: "exception")
  end

  # Validate state parameter to prevent CSRF attacks
  # Compares CSRF token in state with the one stored in session
  def validate_state_parameter(state)
    return false if state.blank?
    return false if session[:oauth_state].blank?

    begin
      # URI.decode_www_form returns array of [key, value] pairs
      state_params = URI.decode_www_form(state).to_h
      received_csrf_token = state_params["csrf_token"]

      # Use secure comparison to prevent timing attacks
      return false if received_csrf_token.blank?

      # Compare tokens securely using constant-time comparison
      stored_token = session[:oauth_state]
      tokens_match = ActiveSupport::SecurityUtils.secure_compare(
        stored_token.to_s,
        received_csrf_token.to_s
      )

      # Clear state from session after validation (one-time use)
      session.delete(:oauth_state) if tokens_match

      tokens_match
    rescue ArgumentError, URI::InvalidURIError => e
      Rails.logger.error("Failed to decode state parameter: #{e.message}")
      false
    end
  end

  # Extract validated state (without CSRF token) for passing to interaction
  # Returns state string with only business parameters (e.g., professional_id)
  # This is called after validate_state_parameter succeeds, so state is safe to decode
  def extract_validated_state(state)
    return nil if state.blank?

    begin
      # URI.decode_www_form returns array of [key, value] pairs
      state_params = URI.decode_www_form(state).to_h
      state_params.delete("csrf_token") # Remove CSRF token, keep business params

      # Validate that remaining params are expected
      return nil if state_params.empty?

      # Validate against known business parameters (e.g., professional_id)
      allowed_params = %w[professional_id] # Add other allowed params as needed
      state_params = state_params.slice(*allowed_params)

      return nil if state_params.empty?

      # Re-encode only business parameters
      URI.encode_www_form(state_params)
    rescue ArgumentError, URI::InvalidURIError => e
      Rails.logger.error("Failed to extract validated state: #{e.message}")
      nil
    end
  end

  # Format error message for display
  # In development: shows detailed error information for debugging
  # In production: always returns generic user-friendly message
  def format_error_message(message, exception: nil)
    if Rails.env.development?
      # In development, show detailed error information
      if exception
        "#{exception.class}: #{exception.message}\n\n#{message}"
      else
        message
      end
    else
      # In production, always return generic user-friendly message
      # Never expose internal error details to users
      "Please try again or contact support if the problem persists."
    end
  end
end
