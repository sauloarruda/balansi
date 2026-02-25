module Professionals
  module Patients
    module ClinicalAssessments
      class UpdateInteraction < ActiveInteraction::Base
        PERMITTED_ATTRIBUTES = %i[
          daily_calorie_goal
          bmr
          steps_goal
          hydration_goal
        ].freeze

        object :patient, class: Patient
        object :professional, class: Professional
        object :assessment_params, class: ActionController::Parameters

        def execute
          return nil unless professional.owner_of?(patient)

          patient.assign_attributes(permitted_attributes)
          patient.clinical_assessment_last_updated_at = Time.current

          return nil unless patient.save

          patient
        end

        private

        def permitted_attributes
          assessment_params.permit(*PERMITTED_ATTRIBUTES).to_h
        end
      end
    end
  end
end
