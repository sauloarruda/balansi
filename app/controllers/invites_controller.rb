# Note: inherits from ActionController::Base (not ApplicationController) intentionally.
# ApplicationController adds authenticate_user! and other before-actions that would block
# unauthenticated visitors. This controller only redirects, so CSRF protection is not needed.
class InvitesController < ActionController::Base
  def show
    professional = Professional.find_by(invite_code: params[:invite_code].to_s.upcase)
    redirect_to professional ? "/auth/sign_up?invite_code=#{professional.invite_code}" : "/auth/sign_in"
  end
end
