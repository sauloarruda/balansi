class JournalsController < ApplicationController
  before_action :set_current_date, only: [ :index, :show ]

  def index
    redirect_to journal_path(date: @current_date.iso8601)
  end

  def show
    @journal = build_journal_payload(@current_date)
    @patient = build_patient_payload
  end

  def close
    if request.get?
      date = parse_date_param(params[:date]) || Date.current
      @journal = build_journal_payload(date)
      @patient = build_patient_payload
      return
    end

    flash[:notice] = "Day closed successfully! (Mock implementation)"
    redirect_to journal_path(date: params[:date])
  end

  private

  def set_current_date
    @current_date = parse_date_param(params[:date]) || Date.current
  end

  def parse_date_param(raw_date)
    return nil if raw_date.blank?

    Date.iso8601(raw_date)
  rescue ArgumentError
    nil
  end

  def build_patient_payload
    {
      id: current_patient.id,
      user_id: current_patient.user_id,
      daily_calorie_goal: current_patient.daily_calorie_goal,
      bmr: current_patient.bmr,
      steps_goal: current_patient.steps_goal,
      hydration_goal: current_patient.hydration_goal
    }
  end

  def build_journal_payload(date)
    journal = current_patient.journals.includes(:meals, :exercises).find_by(date: date)
    return empty_journal_payload(date) unless journal

    {
      id: journal.id,
      patient_id: journal.patient_id,
      date: journal.date,
      closed_at: journal.closed_at,
      calories_consumed: journal.calories_consumed,
      calories_burned: journal.calories_burned,
      score: journal.score,
      feedback_positive: journal.feedback_positive,
      feedback_improvement: journal.feedback_improvement,
      feeling_today: journal.feeling_today,
      sleep_quality: journal.sleep_quality,
      hydration_quality: journal.hydration_quality,
      steps_count: journal.steps_count,
      daily_note: journal.daily_note,
      meals: journal.meals.order(:created_at).map { |meal| meal_payload(meal) },
      exercises: journal.exercises.order(:created_at).map { |exercise| exercise_payload(exercise) }
    }
  end

  def empty_journal_payload(date)
    {
      id: nil,
      patient_id: current_patient.id,
      date: date,
      closed_at: nil,
      calories_consumed: nil,
      calories_burned: nil,
      score: nil,
      feedback_positive: nil,
      feedback_improvement: nil,
      feeling_today: nil,
      sleep_quality: nil,
      hydration_quality: nil,
      steps_count: nil,
      daily_note: nil,
      meals: [],
      exercises: []
    }
  end

  def meal_payload(meal)
    {
      id: meal.id,
      journal_id: meal.journal_id,
      meal_type: meal.meal_type.to_s,
      description: meal.description,
      proteins: meal.proteins,
      carbs: meal.carbs,
      fats: meal.fats,
      calories: meal.calories,
      gram_weight: meal.gram_weight,
      ai_comment: meal.ai_comment,
      feeling: meal.feeling,
      status: meal.status.to_s,
      created_at: meal.created_at
    }
  end

  def exercise_payload(exercise)
    {
      id: exercise.id,
      journal_id: exercise.journal_id,
      description: exercise.description,
      duration: exercise.duration,
      calories: exercise.calories,
      neat: exercise.neat,
      structured_description: exercise.structured_description,
      status: exercise.status.to_s,
      created_at: exercise.created_at
    }
  end
end
