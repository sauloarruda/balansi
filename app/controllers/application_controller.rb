class ApplicationController < ActionController::Base
  include Authentication
  include BrowserLanguage
  include BrowserTimezone

  around_action :use_user_timezone
  before_action :ensure_current_patient!

  helper_method :current_patient

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def current_patient
    return nil unless current_user

    @current_patient ||= current_user.patient
  end

  def ensure_current_patient!
    return if current_user.nil?
    return if current_patient

    head :forbidden
  end

  def use_user_timezone(&block)
    return yield unless current_user&.timezone.present?

    Time.use_zone(current_user.timezone, &block)
  end
end
