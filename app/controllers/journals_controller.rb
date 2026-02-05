class JournalsController < ApplicationController
  before_action :ensure_current_patient!
  before_action :set_current_date, only: [ :index, :show ]

  def index
    redirect_to journal_path(date: @current_date.iso8601)
  end

  def show
    @journal = current_patient.journals.find_by(date: @current_date) || current_patient.journals.build(date: @current_date)
    @meals = @journal.persisted? ? @journal.meals.order(:created_at) : Meal.none
    @exercises = @journal.persisted? ? @journal.exercises.order(:created_at) : Exercise.none
    @patient = current_patient
  end

  def close
    if request.patch?
      flash[:notice] = "Day closed successfully! (Mock implementation)"
      redirect_to journal_path(date: params[:date])
      return
    end

    date = parse_date_param(params[:date]) || Date.current
    @journal = current_patient.journals.find_by(date: date) || current_patient.journals.build(date: date)
    @meals = @journal.persisted? ? @journal.meals.order(:created_at) : Meal.none
    @exercises = @journal.persisted? ? @journal.exercises.order(:created_at) : Exercise.none
    @patient = current_patient
  end

  private

  def ensure_current_patient!
    return if current_patient

    head :forbidden
  end

  def set_current_date
    @current_date = parse_date_param(params[:date]) || Date.current
  end

  def parse_date_param(raw_date)
    return nil if raw_date.blank?

    Date.iso8601(raw_date)
  rescue ArgumentError
    nil
  end
end
