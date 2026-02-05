class Auth::SessionsController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :ensure_current_patient!

  # Initiate OAuth authentication flow (sign in or sign up)
  #
  # Generates a CSRF token and redirects user to Cognito Hosted UI for authentication.
  # The CSRF token is stored in session and included in the state parameter for validation
  # on callback to prevent CSRF attacks.
  #
  # @note This action:
  #   - Generates a cryptographically secure CSRF token (32 bytes, base64url encoded)
  #   - Stores CSRF token in session[:oauth_state] for validation on callback
  #   - Includes optional professional_id parameter if provided in request
  #   - Detects browser language for Cognito localization
  #   - Redirects to appropriate Cognito endpoint based on request path:
  #     - /auth/sign_up → Cognito signup URL
  #     - /auth/sign_in → Cognito login URL
  #
  # @example Sign in request
  #   GET /auth/sign_in
  #   # Redirects to Cognito login page
  #
  # @example Sign up request with professional_id
  #   GET /auth/sign_up?professional_id=123
  #   # Redirects to Cognito signup page with professional_id in state parameter
  #
  # @raise [CognitoService::MissingCredentialsError] If Cognito credentials are not configured
  #   Renders error view with 503 Service Unavailable status
  #
  # @see Auth::CallbacksController#show Validates the CSRF token from state parameter
  # @see CognitoService.login_url Generates the Cognito login URL
  # @see CognitoService.signup_url Generates the Cognito signup URL
  def new
    # Generate CSRF token and store in session for validation on callback
    csrf_token = generate_state_token
    session[:oauth_state] = csrf_token

    # Build state parameter: CSRF token + optional professional_id
    state_params = { csrf_token: csrf_token }
    state_params[:professional_id] = params[:professional_id] if params[:professional_id].present?
    state = URI.encode_www_form(state_params)

    locale = detect_browser_language

    # Determine if this is a sign-up or sign-in request
    if request.path == "/auth/sign_up"
      redirect_to CognitoService.signup_url(state: state, locale: locale), allow_other_host: true
    else
      redirect_to CognitoService.login_url(state: state, locale: locale), allow_other_host: true
    end
  rescue CognitoService::MissingCredentialsError => e
    render :new, status: :service_unavailable
  end

  # Logout user and invalidate session
  #
  # Clears the Rails session and redirects to Cognito logout endpoint to invalidate
  # the Cognito session as well. After Cognito logout, user is redirected back to
  # the logout_uri configured in credentials (typically the application root).
  #
  # @note This action:
  #   - Clears Rails session using reset_session (regenerates session ID, prevents session fixation)
  #   - Redirects to Cognito logout endpoint to invalidate Cognito session
  #   - Uses status :see_other (303) for proper redirect semantics
  #   - The logout_uri must match exactly what's configured in Terraform (logout_urls)
  #
  # @example Logout request
  #   DELETE /auth/sign_out
  #   # Clears session and redirects to Cognito logout, then back to app root
  #
  # @raise [CognitoService::MissingCredentialsError] If Cognito credentials are not configured
  #   Falls back to redirecting to root_path without Cognito logout
  #
  # @see CognitoService.logout_url Generates the Cognito logout URL
  def destroy
    # Clear Rails session first
    reset_session

    # Redirect to Cognito logout to invalidate Cognito session
    # This ensures user is fully logged out from Cognito as well
    # After Cognito logout, it will redirect back to logout_uri (configured in credentials: http://localhost:3000/)
    # Note: logout_uri must match exactly what's configured in Terraform logout_urls
    redirect_to CognitoService.logout_url, allow_other_host: true, status: :see_other
  rescue CognitoService::MissingCredentialsError => e
    # If Cognito service is not configured, just redirect to home
    redirect_to root_path, status: :see_other
  end

  private

  # Generate a secure random token for CSRF protection
  # Uses SecureRandom.urlsafe_base64 for cryptographically secure token
  def generate_state_token
    SecureRandom.urlsafe_base64(32)
  end
end
