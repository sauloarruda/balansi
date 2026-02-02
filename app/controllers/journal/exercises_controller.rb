module Journal
  class ExercisesController < ApplicationController
    before_action :set_journal

    def new
      @exercise = mock_new_exercise
    end

    def create
      # In Phase 1, just simulate LLM processing delay
      flash[:notice] = "Exercise submitted! Processing with AI... (Mock)"
      redirect_to journal_exercise_path(journal_id: @journal[:date].to_s, id: 1)
    end

    def show
      @exercise = mock_exercise_for_review
      @journal = @journal || mock_journal
    end

    def edit
      @exercise = mock_exercise_for_review
    end

    def update
      # In Phase 1, just redirect with success
      flash[:notice] = "Exercise updated! (Mock)"
      redirect_to journal_path(date: @journal[:date].to_s)
    end

    def destroy
      flash[:notice] = "Exercise deleted! (Mock)"
      redirect_to journal_path(date: @journal[:date].to_s)
    end

    private

    def set_journal
      date_param = params[:journal_date] || params[:journal_id]
      date = date_param ? Date.parse(date_param) : Date.current
      @journal = mock_journal_for_date(date)
    rescue ArgumentError
      @journal = mock_journal_for_date(Date.current)
    end

    def mock_new_exercise
      {
        description: "",
        date: params[:date] || Date.current
      }
    end

    def mock_exercise_for_review
      {
        id: 1,
        journal_id: @journal[:id],
        description: "5 km moderate run in the park",
        duration: 30,
        calories: 250,
        neat: 0,
        structured_description: "5 km moderate run",
        status: "pending_patient"
      }
    end

    def mock_journal
      {
        id: 1,
        date: Date.current
      }
    end

    def mock_journal_for_date(date)
      {
        id: 1,
        date: date
      }
    end
  end
end
