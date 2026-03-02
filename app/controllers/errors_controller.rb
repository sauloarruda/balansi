class ErrorsController < ApplicationController
  skip_before_action :development_test_user_login!, raise: false
  skip_before_action :authenticate_user!
  skip_before_action :ensure_current_patient!
  skip_before_action :ensure_patient_personal_profile_completed!

  def forbidden
    render :forbidden, status: :forbidden
  end

  def not_found
    render :not_found, status: :not_found
  end

  def internal_server_error
    render :internal_server_error, status: :internal_server_error
  end
end
