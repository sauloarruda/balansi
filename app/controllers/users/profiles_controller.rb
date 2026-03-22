module Users
  class ProfilesController < ApplicationController
    skip_before_action :ensure_current_patient!
    skip_before_action :ensure_patient_personal_profile_completed!

    def show
    end

    def update
      if current_user.update(profile_params)
        redirect_to user_profile_path, notice: t("users.profile.messages.updated")
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    def profile_params
      params.require(:user).permit(:language, :timezone)
    end
  end
end
