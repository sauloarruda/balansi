module Professionals
  module Patients
    class BaseController < Professionals::BaseController
      before_action :set_patient
      before_action :authorize_access!
      before_action :authorize_owner!

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
    end
  end
end
