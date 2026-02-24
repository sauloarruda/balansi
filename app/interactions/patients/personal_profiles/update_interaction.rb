module Patients
  module PersonalProfiles
    class UpdateInteraction < ActiveInteraction::Base
      PERMITTED_PROFILE_ATTRIBUTES = %i[
        gender
        birth_date
        weight_kg
        height_cm
        phone_country
        phone_national_number
      ].freeze

      object :patient, class: Patient
      object :profile_params, class: ActionController::Parameters

      attr_reader :birth_date_input, :phone_country, :phone_national_number

      def execute
        assign_form_inputs

        parsed_birth_date = parse_localized_birth_date(birth_date_input)
        if parsed_birth_date == :invalid
          assign_personal_profile_attributes(except_birth_date: true)
          patient.birth_date = nil
          patient.errors.add(:birth_date, I18n.t("patient_personal_profile.messages.birth_date_invalid"))
          copy_patient_errors_to_interaction
          return nil
        end

        assign_personal_profile_attributes(except_birth_date: true)
        patient.birth_date = parsed_birth_date
        phone_valid = apply_phone_e164_from_local_input

        profile_valid = patient.valid?(:patient_personal_profile)

        unless phone_valid
          patient.errors.delete(:phone_e164)
          patient.errors.add(:phone_national_number, I18n.t("patient_personal_profile.messages.phone_invalid"))
        else
          remap_phone_errors_to_form_field
        end

        unless profile_valid && phone_valid
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
        @phone_country = Patients::PersonalProfiles::PhoneLocalization.normalize_country(profile_attributes[:phone_country])
        @phone_national_number = profile_attributes[:phone_national_number].to_s
      end

      def profile_attributes
        @profile_attributes ||= begin
          permitted_params = profile_params.permit(*PERMITTED_PROFILE_ATTRIBUTES)

          permitted_params.to_h.symbolize_keys
        end
      end

      VIRTUAL_PHONE_FIELDS = %i[phone_country phone_national_number].freeze

      def assign_personal_profile_attributes(except_birth_date: false)
        attributes = profile_attributes.except(*VIRTUAL_PHONE_FIELDS)
        attributes = attributes.except(:birth_date) if except_birth_date
        patient.assign_attributes(attributes)
      end

      def parse_localized_birth_date(raw_birth_date)
        Patients::PersonalProfiles::BirthDateLocalization.parse(raw_birth_date)
      end

      def apply_phone_e164_from_local_input
        if phone_national_number.blank?
          patient.phone_e164 = nil
          return true
        end

        parsed_phone = Patients::PersonalProfiles::PhoneLocalization.parse_local_input(phone_national_number, phone_country)
        if parsed_phone.valid?
          patient.phone_e164 = parsed_phone.full_e164
          true
        else
          patient.phone_e164 = nil
          false
        end
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
