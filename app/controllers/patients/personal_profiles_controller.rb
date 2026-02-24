module Patients
  class PersonalProfilesController < ApplicationController
    skip_before_action :ensure_patient_personal_profile_completed!, only: [ :show, :update ]
    before_action :set_patient

    def show
      if @patient.personal_profile_completed?
        redirect_to root_path
        return
      end

      @birth_date_input = Patients::PersonalProfiles::BirthDateLocalization.format(@patient.birth_date)
      assign_phone_inputs_from_patient
    end

    def update
      result = Patients::PersonalProfiles::UpdateInteraction.run(
        patient: @patient,
        profile_params: personal_profile_params
      )

      @birth_date_input = result.birth_date_input
      @phone_country = result.phone_country
      @phone_national_number = result.phone_national_number

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
      params.require(:patient).permit(
        :gender,
        :birth_date,
        :weight_kg,
        :height_cm,
        :phone_country,
        :phone_national_number
      )
    end

    def assign_phone_inputs_from_patient
      parsed_phone = Phonelib.parse(@patient.phone_e164)
      if parsed_phone.valid?
        @phone_country = normalize_phone_country(parsed_phone.country)
        @phone_national_number = parsed_phone.national
      else
        @phone_country = default_phone_country
        @phone_national_number = nil
      end
    end

    def normalize_phone_country(raw_country)
      country_code = raw_country.to_s.upcase
      return default_phone_country if country_code.blank?
      return country_code if country_code.match?(/\A[A-Z]{2}\z/)

      default_phone_country
    end

    def default_phone_country
      "BR"
    end
  end
end
