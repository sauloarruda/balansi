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
      perform_close
      return
    end

    date = parse_date_param(params[:date]) || Date.current
    @journal = current_patient.journals.find_by(date: date) || current_patient.journals.build(date: date)
    @meals = @journal.persisted? ? @journal.meals.order(:created_at) : Meal.none
    @exercises = @journal.persisted? ? @journal.exercises.order(:created_at) : Exercise.none
    @patient = current_patient
  end

  private

  def perform_close
    date = parse_date_param(params[:date]) || Date.current
    @journal = current_patient.journals.find_by(date: date)

    unless @journal
      redirect_to journal_path(date: date.iso8601), alert: t("journals.close.flash.journal_not_found")
      return
    end

    if @journal.closed? && !@journal.editable?
      redirect_to journal_path(date: date.iso8601), alert: t("journals.close.flash.read_only")
      return
    end

    @journal.assign_attributes(close_journal_params)
    @journal.meals.pending.delete_all
    @journal.exercises.pending.delete_all

    @journal.calories_consumed = @journal.calculate_calories_consumed
    @journal.calories_burned = @journal.calculate_calories_burned
    @journal.closed_at = Time.current unless @journal.closed?
    @journal.save!

    result = Journal::ScoreDailyJournalInteraction.run(
      journal: @journal,
      user_id: current_user.id,
      user_language: current_user.language
    )

    if result.valid?
      flash[:notice] = t("journals.close.flash.success")
    else
      flash[:alert] = t("journals.close.flash.success_no_score")
    end

    redirect_to journal_path(date: date.iso8601)
  end

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

  def close_journal_params
    params.permit(:feeling_today, :sleep_quality, :hydration_quality, :steps_count, :daily_note)
  end
end

