module Patients
  module ProfessionalAccesses
    class CreateInteraction < ActiveInteraction::Base
      object :patient, class: Patient
      object :granting_user, class: User
      string :professional_email

      def execute
        professional = find_professional_by_email
        return nil if errors.any?
        return nil unless valid_share_target?(professional)

        access = PatientProfessionalAccess.new(
          patient: patient,
          professional: professional,
          granted_by_patient_user: granting_user
        )

        if access.save
          access
        else
          access.errors.each { |e| errors.add(e.attribute, e.message) }
          nil
        end
      end

      private

      def find_professional_by_email
        user = User.find_by(email: professional_email.to_s.strip.downcase)
        professional = user&.professional

        if professional.nil?
          errors.add(:professional_email, I18n.t("patient.professional_accesses.errors.professional_not_found"))
          return nil
        end

        professional
      end

      def valid_share_target?(professional)
        return false if professional.nil?

        if patient.professional_id == professional.id
          errors.add(:professional_email, I18n.t("patient.professional_accesses.errors.already_owner"))
          return false
        end

        if PatientProfessionalAccess.exists?(patient: patient, professional: professional)
          errors.add(:professional_email, I18n.t("patient.professional_accesses.errors.already_shared"))
          return false
        end

        true
      end
    end
  end
end
