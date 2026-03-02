module Patients
  module ProfessionalAccesses
    class DestroyInteraction < ActiveInteraction::Base
      object :patient, class: Patient
      integer :access_id

      def execute
        access = PatientProfessionalAccess.find_by(id: access_id, patient: patient)

        if access.nil?
          errors.add(:base, :not_found)
          return nil
        end

        access.destroy
        access
      end
    end
  end
end
