# BrowserLanguage concern
#
# When included in a controller, this concern:
# - Adds a before_action that sets the Rails locale based on browser language
# - Provides a helper_method :detect_browser_language available in views
# - Detects language from the Accept-Language HTTP header (supports :pt and :en)
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

  # Detect browser language from Accept-Language header
  # Returns locale symbol (:pt or :en), defaults to :pt
  def detect_browser_language
    accept_language = request.headers["Accept-Language"]
    return :pt if accept_language.blank?

    languages = parse_languages(accept_language)
    return :pt if languages.empty?

    detect_locale_from_languages(languages)
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
