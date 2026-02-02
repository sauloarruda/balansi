class JournalsController < ApplicationController
  before_action :set_current_date, only: [:index, :show]

  def index
    # Redirect to today's journal
    redirect_to journal_path(date: @current_date)
  end

  def show
    @journal = mock_journal_for_date(@current_date)
    @patient = mock_patient
  end

  def close
    if request.get?
      # Show close form
      date = params[:date] ? Date.parse(params[:date]) : Date.current
      @journal = mock_journal_for_date(date)
      @patient = mock_patient
    elsif request.patch?
      # Process close day
      # In Phase 1, just redirect back to journal with flash message
      flash[:notice] = "Day closed successfully! (Mock implementation)"
      redirect_to journal_path(date: params[:date])
    end
  rescue ArgumentError
    if request.get?
      date = Date.current
      @journal = mock_journal_for_date(date)
      @patient = mock_patient
    end
  end

  private

  def set_current_date
    date_param = params[:date]
    @current_date = date_param ? Date.parse(date_param) : Date.current
  rescue ArgumentError
    @current_date = Date.current
  end

  def mock_journal_for_date(date)
    # Mock journal data with various states for testing
    closed = date < Date.current
    has_pending = date == Date.current

    {
      id: 1,
      patient_id: 1,
      date: date,
      closed_at: closed ? date.end_of_day : nil,
      calories_consumed: closed ? 1850 : nil,
      calories_burned: closed ? 2100 : nil,
      score: closed ? 4 : nil,
      feedback_positive: closed ? "Good protein intake and consistent exercise routine" : nil,
      feedback_improvement: closed ? "Consider reducing evening snacks to improve caloric balance" : nil,
      feeling_today: closed ? 3 : nil,
      sleep_quality: closed ? 2 : nil,
      hydration_quality: closed ? 3 : nil,
      steps_count: closed ? 8000 : nil,
      daily_note: closed ? "Feeling good today!" : nil,
      meals: mock_meals(date, has_pending),
      exercises: mock_exercises(date, has_pending)
    }
  end

  def mock_meals(date, include_pending)
    meals = [
      {
        id: 1,
        journal_id: 1,
        meal_type: "breakfast",
        description: "Oatmeal with fruits and nuts",
        proteins: 15,
        carbs: 45,
        fats: 12,
        calories: 380,
        gram_weight: 250,
        ai_comment: "Balanced breakfast with good protein and healthy fats",
        feeling: 1,
        status: "confirmed",
        created_at: date.beginning_of_day + 7.hours
      },
      {
        id: 2,
        journal_id: 1,
        meal_type: "lunch",
        description: "Grilled chicken with rice and vegetables",
        proteins: 35,
        carbs: 55,
        fats: 15,
        calories: 520,
        gram_weight: 400,
        ai_comment: "Great protein source with balanced macros",
        feeling: 1,
        status: "confirmed",
        created_at: date.beginning_of_day + 13.hours
      },
      {
        id: 3,
        journal_id: 1,
        meal_type: "snack",
        description: "Apple with peanut butter",
        proteins: 8,
        carbs: 20,
        fats: 10,
        calories: 180,
        gram_weight: 150,
        ai_comment: "Healthy snack with good protein",
        feeling: 1,
        status: "confirmed",
        created_at: date.beginning_of_day + 16.hours
      }
    ]

    if include_pending
      meals << {
        id: 4,
        journal_id: 1,
        meal_type: "dinner",
        description: "Fish with sweet potato and salad",
        proteins: 30,
        carbs: 40,
        fats: 12,
        calories: 380,
        gram_weight: 350,
        ai_comment: "Excellent dinner choice with lean protein and complex carbs",
        feeling: 1,
        status: "pending_patient",
        created_at: date.beginning_of_day + 19.hours
      }
    end

    meals
  end

  def mock_exercises(date, include_pending)
    exercises = [
      {
        id: 1,
        journal_id: 1,
        description: "5 km moderate walk",
        duration: 45,
        calories: 250,
        neat: 0,
        structured_description: "5 km moderate walk",
        status: "confirmed",
        created_at: date.beginning_of_day + 8.hours
      },
      {
        id: 2,
        journal_id: 1,
        description: "Light strength training",
        duration: 30,
        calories: 150,
        neat: 0,
        structured_description: "Light strength training",
        status: "confirmed",
        created_at: date.beginning_of_day + 17.hours
      }
    ]

    if include_pending
      exercises << {
        id: 3,
        journal_id: 1,
        description: "Yoga session",
        duration: 20,
        calories: 80,
        neat: 0,
        structured_description: "Yoga session",
        status: "pending_patient",
        created_at: date.beginning_of_day + 20.hours
      }
    end

    exercises
  end

  def mock_patient
    {
      id: 1,
      user_id: current_user.id,
      daily_calorie_goal: 2000,
      bmr: 1800,
      steps_goal: 8000,
      hydration_goal: 2000
    }
  end
end
