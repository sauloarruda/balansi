module Professionals
  module Patients
    class ClinicalAssessmentsController < Professionals::BaseController
      before_action :set_patient
      before_action :authorize_access!
      before_action :authorize_owner!

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

      def set_patient
        @patient = Patient.find(params[:patient_id])
      end

      def authorize_access!
        return if current_professional.can_access?(@patient)

        head :forbidden
      end

      def authorize_owner!
        return if current_professional.owner_of?(@patient)

        head :forbidden
      end

      def assessment_params
        params.require(:patient).permit(
          *Professionals::Patients::ClinicalAssessments::UpdateInteraction::PERMITTED_ATTRIBUTES
        )
      end
    end
  end
end
