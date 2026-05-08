module Professionals
  module Patients
    class BaseController < Professionals::BaseController
      before_action :set_patient
      before_action :authorize_access!
      before_action :authorize_owner!

      private

      def set_patient
        id = params[:patient_id] || params[:id]
        @patient = Patient.find(id)
      end

      def authorize_access!
        return if current_professional.can_access?(@patient)

        render_forbidden
      end

      def authorize_owner!
        return if current_professional.owner_of?(@patient) || current_professional.admin?

        render_forbidden
      end
    end
  end
end
