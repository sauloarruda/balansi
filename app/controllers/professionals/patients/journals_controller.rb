module Professionals
  module Patients
    class JournalsController < Professionals::Patients::BaseController
      skip_before_action :authorize_owner!

      def show
        date = parse_date_param(params[:date]) || Date.current

        @journal = @patient.journals.find_by(date: date) || @patient.journals.build(date: date)
        @meals = @journal.persisted? ? @journal.meals.includes(meal_recipe_references: :recipe).order(:created_at) : Meal.none
        @exercises = @journal.persisted? ? @journal.exercises.order(:created_at) : Exercise.none

        render "journals/show"
      end

      def today
        redirect_to journal_professional_patient_path(@patient, date: Date.current.iso8601)
      end

      private

      def parse_date_param(raw_date)
        return nil if raw_date.blank?

        Date.iso8601(raw_date)
      rescue ArgumentError
        nil
      end
    end
  end
end
