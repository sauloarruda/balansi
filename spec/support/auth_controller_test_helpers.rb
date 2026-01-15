# Helper methods for auth controller specs

module AuthControllerTestHelpers
  # Constants for test values
  CSRF_TOKEN_LENGTH = 32
  CODE_CACHE_EXPIRATION = 5.minutes

  # Setup valid session with CSRF token and browser detection stubs
  def setup_valid_session(csrf_token:)
    session[:oauth_state] = csrf_token
    allow(controller).to receive(:detect_browser_timezone).and_return("America/Sao_Paulo")
    allow(controller).to receive(:detect_browser_language).and_return("pt")
  end

  # Create a valid authentication result double
  def create_valid_result(user:, refresh_token:)
    double(
      valid?: true,
      result: { user: user, refresh_token: refresh_token },
      errors: double(full_messages: [])
    )
  end

  # Create an invalid authentication result double
  def create_invalid_result(error_message: "Authentication failed")
    double(
      valid?: false,
      result: nil,
      errors: double(full_messages: [ error_message ])
    )
  end

  # Setup URI stubbing for error injection
  # This simplifies the complex call-counting pattern
  def stub_uri_decode_with_error_on_second_call(error_class, error_message)
    call_count = 0
    allow(URI).to receive(:decode_www_form) do |arg|
      call_count += 1
      if call_count == 1
        URI.decode_www_form(arg)
      else
        raise error_class.new(error_message)
      end
    end
  end

  # Clear auth code cache entries to ensure test isolation
  # This is more targeted than clearing the entire cache
  def clear_auth_code_cache
    # Clear any auth code cache entries that might exist
    # In test environment, we can safely clear the entire cache
    Rails.cache.clear if Rails.env.test?
  end

  # Create state parameter with CSRF token and optional business params
  def build_state_param(csrf_token:, professional_id: nil)
    params = { "csrf_token" => csrf_token }
    params["professional_id"] = professional_id if professional_id.present?
    URI.encode_www_form(params)
  end
end

RSpec.configure do |config|
  config.include AuthControllerTestHelpers, type: :controller
end
