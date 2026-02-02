module Journal
  class MealsController < ApplicationController
    before_action :set_journal

    def new
      @meal = mock_new_meal
    end

    def create
      # In Phase 1, just simulate LLM processing delay
      # In real implementation, this would call AnalyzeMealInteraction
      flash[:notice] = "Meal submitted! Processing with AI... (Mock)"
      redirect_to journal_meal_path(journal_id: @journal[:date].to_s, id: 1)
    end

    def show
      @meal = mock_meal_for_review
      @journal = @journal || mock_journal
    end

    def edit
      @meal = mock_meal_for_review
    end

    def update
      # In Phase 1, just redirect with success
      flash[:notice] = "Meal updated! (Mock)"
      redirect_to journal_path(date: @journal[:date].to_s)
    end

    def destroy
      flash[:notice] = "Meal deleted! (Mock)"
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

    def mock_new_meal
      {
        meal_type: params[:meal_type] || "breakfast",
        description: "",
        date: params[:date] || Date.current
      }
    end

    def mock_meal_for_review
      {
        id: 1,
        journal_id: @journal[:id],
        meal_type: "dinner",
        description: "Fish with sweet potato and salad",
        proteins: 30,
        carbs: 40,
        fats: 12,
        calories: 380,
        gram_weight: 350,
        ai_comment: "Excellent dinner choice with lean protein and complex carbs. The fish provides high-quality protein while sweet potato offers complex carbohydrates and fiber.",
        feeling: 1,
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
