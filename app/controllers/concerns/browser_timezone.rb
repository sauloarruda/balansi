# BrowserTimezone concern
#
# When included in a controller, this concern:
# - Provides a helper_method :detect_browser_timezone available in views
# - Detects timezone from cookies (set by JavaScript on the client side)
# - Defaults to 'America/Sao_Paulo' if no timezone cookie is present
#
# The timezone detection relies on JavaScript to set the timezone cookie,
# which should be set when the page loads on the client side.
module BrowserTimezone
  extend ActiveSupport::Concern

  included do
    helper_method :detect_browser_timezone
  end

  private

  # Detect browser timezone from cookies
  # Returns timezone string in IANA format (e.g., 'America/Sao_Paulo'), defaults to 'America/Sao_Paulo'
  def detect_browser_timezone
    # Check for timezone in cookies (set by JavaScript)
    # JavaScript Intl.DateTimeFormat returns IANA timezone identifiers
    timezone = cookies[:timezone]
    return timezone if timezone.present?

    # Fallback to default Brazilian timezone in IANA format
    "America/Sao_Paulo"
  end
end
