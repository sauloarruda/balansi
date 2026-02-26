module Professionals
  class BaseController < ApplicationController
    skip_before_action :ensure_current_patient!
    skip_before_action :ensure_patient_personal_profile_completed!
    before_action :ensure_current_professional!

    helper_method :current_professional

    private

    def current_professional
      return nil unless current_user

      @current_professional ||= current_user.professional
    end

    def ensure_current_professional!
      return if current_user.nil?
      return if current_professional.present?

      head :forbidden
    end
  end
end
