# BrowserLanguage concern
#
# When included in a controller, this concern:
# - Adds a before_action that sets the Rails locale based on user language or browser language
# - Provides a helper_method :detect_browser_language available in views
# - For authenticated users: always uses language from database (User#language)
# - For unauthenticated users: uses Accept-Language HTTP header (supports :pt and :en)
# - Defaults to :pt if no language is detected or if an unsupported language is detected
#
# The set_locale method is automatically called before each action to ensure
# I18n.locale is set correctly for the current request.
module BrowserLanguage
  extend ActiveSupport::Concern

  included do
    before_action :set_locale
    helper_method :detect_browser_language
  end

  private

  # Detect browser language from database (if authenticated) or Accept-Language header
  # Priority order: Database (User#language) if authenticated > Accept-Language header > Default (:pt)
  # Returns locale symbol (:pt or :en), defaults to :pt
  def detect_browser_language
    # First, check database (for authenticated users) - always use database if user exists
    if respond_to?(:current_user, true) && current_user
      locale = normalize_locale(current_user.language)
      return locale if valid_locale?(locale)
      # If database has invalid locale, fall through to browser detection
    end

    # Second, fallback to Accept-Language header (for unauthenticated users or invalid DB value)
    accept_language = request.headers["Accept-Language"]
    return :pt if accept_language.blank?

    languages = parse_languages(accept_language)
    return :pt if languages.empty?

    detect_locale_from_languages(languages)
  end

  # Normalize locale parameter to symbol
  # Handles "pt", "pt-BR", "en", "en-US", etc.
  def normalize_locale(locale_string)
    return nil if locale_string.blank?
    locale_string = locale_string.to_s.downcase.strip
    return :pt if locale_string.start_with?("pt")
    return :en if locale_string.start_with?("en")
    nil
  end

  # Check if locale is valid (uses Rails i18n configuration from config/application.rb)
  def valid_locale?(locale)
    return false if locale.nil?
    Rails.application.config.i18n.available_locales.include?(locale)
  end

  def parse_languages(accept_language)
    accept_language.split(",").map do |lang|
      lang_part = lang.split(";").first
      lang_part&.strip&.downcase
    end.compact.reject(&:blank?)
  end

  def detect_locale_from_languages(languages)
    return :pt if languages.any? { |l| l.start_with?("pt") }
    return :en if languages.any? { |l| l.start_with?("en") }

    :pt
  end

  # Set Rails locale based on browser language
  def set_locale
    locale = detect_browser_language
    I18n.locale = locale || I18n.default_locale
  end
end
