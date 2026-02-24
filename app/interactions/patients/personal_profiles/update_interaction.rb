module Patients
  module PersonalProfiles
    class UpdateInteraction < ActiveInteraction::Base
      object :patient, class: Patient
      object :profile_params, class: ActionController::Parameters

      attr_reader :birth_date_input, :phone_country, :phone_national_number

      def execute
        assign_form_inputs

        parsed_birth_date = parse_localized_birth_date(birth_date_input)
        if parsed_birth_date == :invalid
          assign_personal_profile_attributes(except_birth_date: true, except_phone: true)
          patient.birth_date = nil
          patient.errors.add(:birth_date, I18n.t("patient_personal_profile.messages.birth_date_invalid"))
          copy_patient_errors_to_interaction
          return nil
        end

        assign_personal_profile_attributes(except_birth_date: true, except_phone: true)
        patient.birth_date = parsed_birth_date
        phone_valid = apply_phone_e164_from_local_input

        profile_valid = patient.valid?(:patient_personal_profile)
        unless phone_valid
          patient.errors.delete(:phone_e164)
          patient.errors.add(:phone_national_number, I18n.t("patient_personal_profile.messages.phone_invalid"))
        end

        unless profile_valid && phone_valid
          remap_phone_errors_to_form_field
          copy_patient_errors_to_interaction
          return nil
        end

        completion_timestamp = Time.current
        patient.profile_completed_at ||= completion_timestamp
        patient.profile_last_updated_at = completion_timestamp
        patient.save!(context: :patient_personal_profile)
        patient
      end

      private

      def assign_form_inputs
        @birth_date_input = profile_attributes[:birth_date]
        @phone_country = normalize_phone_country(profile_attributes[:phone_country])
        @phone_national_number = profile_attributes[:phone_national_number].to_s
      end

      def profile_attributes
        @profile_attributes ||= begin
          permitted_params = profile_params.permit(
            :gender,
            :birth_date,
            :weight_kg,
            :height_cm,
            :phone_country,
            :phone_national_number
          )

          permitted_params.to_h.symbolize_keys
        end
      end

      def assign_personal_profile_attributes(except_birth_date: false, except_phone: false)
        attributes = except_birth_date ? profile_attributes.except(:birth_date) : profile_attributes
        attributes = attributes.except(:phone_country, :phone_national_number) if except_phone
        patient.assign_attributes(attributes)
      end

      def parse_localized_birth_date(raw_birth_date)
        Patients::PersonalProfiles::BirthDateLocalization.parse(raw_birth_date)
      end

      def apply_phone_e164_from_local_input
        if phone_national_number.blank?
          patient.phone_e164 = nil
          return
        end

        parsed_phone = Phonelib.parse(phone_national_number, phone_country)
        if parsed_phone.valid?
          patient.phone_e164 = parsed_phone.full_e164
          true
        else
          patient.phone_e164 = "invalid"
          false
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

      def copy_patient_errors_to_interaction
        patient.errors.each do |error|
          errors.add(error.attribute, error.message)
        end
      end

      def remap_phone_errors_to_form_field
        phone_e164_messages = patient.errors.delete(:phone_e164)
        Array(phone_e164_messages).each do |message|
          patient.errors.add(:phone_national_number, message)
        end
      end
    end
  end
end
