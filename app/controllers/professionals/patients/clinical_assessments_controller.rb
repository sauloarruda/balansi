module Professionals
  module Patients
    class ClinicalAssessmentsController < Professionals::Patients::BaseController
      def edit
      end

      def update
        result = Professionals::Patients::ClinicalAssessments::UpdateInteraction.run(
          patient: @patient,
          professional: current_professional,
          assessment_params: assessment_params
        )

        if result.result
          redirect_to professional_patient_path(@patient),
            notice: t("professional.patients.clinical_assessment.update.success")
        else
          render :edit, status: :unprocessable_entity
        end
      end

      private

      def assessment_params
        params.require(:patient).permit(
          *Professionals::Patients::ClinicalAssessments::UpdateInteraction::PERMITTED_ATTRIBUTES
        ).to_h
      end
    end
  end
end
