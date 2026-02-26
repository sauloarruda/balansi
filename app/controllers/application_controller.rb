class ApplicationController < ActionController::Base
  include Authentication
  include BrowserLanguage
  include BrowserTimezone

  around_action :use_user_timezone
  before_action :ensure_current_patient!
  before_action :ensure_patient_personal_profile_completed!

  helper_method :current_patient
  helper_method :current_professional

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def current_patient
    return nil unless current_user

    @current_patient ||= current_user.patient
  end

  def current_professional
    nil
  end

  def ensure_current_patient!
    return if current_user.nil?
    return if current_patient

    if current_user.professional.present?
      redirect_to professional_patients_path and return
    end

    head :forbidden
  end

  def ensure_patient_personal_profile_completed!
    return if current_user.nil?
    return unless current_patient
    return if controller_path.start_with?("auth/")
    return if controller_path == "patients/personal_profiles"
    return if current_patient.personal_profile_completed?

    redirect_to patient_personal_profile_path, alert: t("patient_personal_profile.messages.gate_required")
  end

  def use_user_timezone(&block)
    return yield unless current_user&.timezone.present?

    Time.use_zone(current_user.timezone, &block)
  end
end
