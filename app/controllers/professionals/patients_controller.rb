module Professionals
  class PatientsController < BaseController
    before_action :set_patient, only: [ :show ]
    before_action :authorize_access!, only: [ :show ]

    def index
      @patients = current_professional.linked_patients
        .joins(:user)
        .order("users.name ASC")
    end

    def show
    end

    private

    def set_patient
      @patient = Patient.find(params[:id])
    end

    def authorize_access!
      return if current_professional.can_access?(@patient)

      head :forbidden
    end
  end
end
