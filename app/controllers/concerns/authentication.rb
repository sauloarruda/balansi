# Authentication concern
#
# When included in a controller, this concern:
# - Adds a before_action that requires authentication for all actions
# - Provides a helper_method :current_user available in views
# - Redirects unauthenticated users to "/auth/sign_in"
#
# In development only: allows bypassing Cognito by passing ?test_user_id=ID
# to sign in as that user and redirect to the same URL without the param.
#
# The current_user method loads the user from session, handling cases where
# the user might have been deleted while the session is still active.
module Authentication
  extend ActiveSupport::Concern

  included do
    helper_method :current_user
    before_action :development_test_user_login!, if: :development_test_user_login_enabled?
    before_action :authenticate_user!
  end

  private

  # In development, allow signing in via ?test_user_id=ID without Cognito.
  # Sets session and redirects to the same path without the param.
  # Only called when development_test_user_login_enabled? returns true.
  def development_test_user_login!
    session[:user_id] = development_test_user.id
    session.delete(:refresh_token)

    target_url = if request.path.match?(%r{/auth/(sign_in|sign_up)})
      # Avoid staying on auth page (which would redirect to Cognito)
      development_test_user.professional.present? ? professional_patients_path : root_path
    elsif request.query_parameters.except("test_user_id").any?
      "#{request.path}?#{request.query_parameters.except("test_user_id").to_query}"
    else
      request.path
    end
    redirect_to target_url
  end

  def development_test_user_login_enabled?
    Rails.env.development? && request.get? && development_test_user.present?
  end

  def development_test_user
    @development_test_user ||= params[:test_user_id].present? && User.find_by(id: params[:test_user_id])
  end

  # Get the currently authenticated user from session
  #
  # @return [User, nil] The authenticated user if session is valid, nil otherwise
  #
  # @note This method:
  #   - Memoizes the user to avoid multiple database queries per request
  #   - Handles cases where user was deleted while session is still active
  #   - Clears invalid session data (user_id and refresh_token) if user not found
  #
  # @example Check if user is authenticated
  #   if current_user
  #     puts "Hello, #{current_user.name}"
  #   end
  def current_user
    @current_user ||= User.find(session[:user_id]) if session[:user_id]
  rescue ActiveRecord::RecordNotFound
    # User was deleted but session still has user_id
    # Clear invalid session and return nil
    session.delete(:user_id)
    session.delete(:refresh_token)
    nil
  end

  # Require user authentication for the current action
  #
  # Redirects to "/auth/sign_in" if user is not authenticated.
  # Used as a before_action to protect controller actions.
  #
  # @return [void]
  #
  # @example Protect all actions in a controller
  #   class MyController < ApplicationController
  #     include Authentication  # Adds authenticate_user! as before_action
  #   end
  #
  # @example Allow specific actions without authentication
  #   class MyController < ApplicationController
  #     include Authentication
  #     skip_before_action :authenticate_user!, only: [:public_action]
  #   end
  def authenticate_user!
    redirect_to "/auth/sign_in" unless current_user
  end
end
