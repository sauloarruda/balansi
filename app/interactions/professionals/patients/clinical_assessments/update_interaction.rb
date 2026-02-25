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
        hash :assessment_params, strip: false

        def execute
          return nil unless professional.owner_of?(patient)

          patient.assign_attributes(assessment_params)
          patient.clinical_assessment_last_updated_at = Time.current

          return nil unless patient.save

          patient
        end
      end
    end
  end
end
