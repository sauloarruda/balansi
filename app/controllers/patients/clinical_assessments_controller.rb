module Patients
  class ClinicalAssessmentsController < ApplicationController
    def show
      head :not_found
    end

    def update
      if current_patient.update(assessment_params)
        redirect_to journal_path(date: Date.current.iso8601),
          notice: t("patient.clinical_assessment.update.success")
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    def assessment_params
      params.require(:patient).permit(
        :daily_calorie_goal,
        :bmr,
        :steps_goal,
        :hydration_goal,
        :daily_carbs_goal,
        :daily_proteins_goal,
        :daily_fats_goal
      )
    end
  end
end
