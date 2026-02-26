module Patients
  class PersonalProfilesController < ApplicationController
    skip_before_action :ensure_patient_personal_profile_completed!, only: [ :show, :update ]
    before_action :set_patient

    def show
      if @patient.personal_profile_completed? && params[:edit].blank?
        render "professionals/patients/show"
        return
      end

      assign_form_inputs_from_patient
    end

    def update
      result = Patients::PersonalProfiles::UpdateInteraction.run(
        patient: @patient,
        profile_params: personal_profile_params
      )

      assign_form_inputs_from_interaction(result)

      unless result.valid?
        render :show, status: :unprocessable_entity
        return
      end

      redirect_to root_path, notice: t("patient_personal_profile.messages.completed_success")
    end

    private

    def set_patient
      @patient = current_patient
    end

    def personal_profile_params
      params.require(:patient).permit(*Patients::PersonalProfiles::UpdateInteraction::PERMITTED_PROFILE_ATTRIBUTES)
    end

    def assign_form_inputs_from_patient
      @birth_date_input = Patients::PersonalProfiles::BirthDateLocalization.format(@patient.birth_date)
      phone_input = Patients::PersonalProfiles::PhoneLocalization.local_input_from_e164(@patient.phone_e164)
      @phone_country = phone_input[:country]
      @phone_national_number = phone_input[:national_number]
    end

    def assign_form_inputs_from_interaction(result)
      @birth_date_input = result.birth_date_input
      @phone_country = result.phone_country
      @phone_national_number = result.phone_national_number
    end
  end
end
