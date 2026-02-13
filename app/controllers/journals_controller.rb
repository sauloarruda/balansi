class JournalsController < ApplicationController
  before_action :set_current_date, only: [ :index, :show, :today ]
  before_action :redirect_future_dates, only: [ :show ]

  def index
    redirect_to journal_path(date: @current_date.iso8601)
  end

  def show
    load_journal_context(@current_date)
  end

  def today
    load_journal_context(Date.current)
    render :show
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

  def load_journal_context(date)
    @journal = current_patient.journals.find_by(date: date) || current_patient.journals.build(date: date)
    @meals = @journal.persisted? ? @journal.meals.order(:created_at) : Meal.none
    @exercises = @journal.persisted? ? @journal.exercises.order(:created_at) : Exercise.none
    @patient = current_patient
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

  def redirect_future_dates
    return unless @current_date > Date.current

    redirect_to today_journals_path
  end
end
