module Patients
  class ProfessionalAccessesController < ApplicationController
    def index
      @accesses = current_patient.patient_professional_accesses.includes(professional: :user)
    end

    def create
      result = Patients::ProfessionalAccesses::CreateInteraction.run(
        patient: current_patient,
        granting_user: current_user,
        professional_email: params.dig(:professional_access, :professional_email).to_s
      )

      if result.valid?
        redirect_to patient_professional_accesses_path,
          notice: t("patient.professional_accesses.messages.shared_success")
      else
        @accesses = current_patient.patient_professional_accesses.includes(professional: :user)
        @professional_email = params.dig(:professional_access, :professional_email)
        @errors = result.errors
        render :index, status: :unprocessable_entity
      end
    end
  end
end
