require "rails_helper"

RSpec.describe JournalsController, type: :controller do
  include ActiveSupport::Testing::TimeHelpers
  render_views

  before do
    create(:journal)
    session[:user_id] = User.find(1001).id
  end

  describe "GET #index" do
    it "redirects to today's journal date in the user's timezone" do
      travel_to(Time.utc(2026, 2, 5, 14, 0, 0)) do
        get :index
      end

      expect(response).to redirect_to("/journals/2026-02-05")
    end

    it "uses user timezone boundaries when utc day differs" do
      User.find(1001).update!(timezone: "America/Los_Angeles")

      travel_to(Time.utc(2026, 2, 5, 7, 30, 0)) do
        get :index
      end

      expect(response).to redirect_to("/journals/2026-02-04")
    end
  end

  describe "GET #today" do
    it "renders today's journal without redirecting to a dated URL" do
      travel_to(Time.zone.local(2026, 2, 5, 12, 0, 0)) do
        get :today
      end

      expect(response).to have_http_status(:ok)
      journal_payload = controller.instance_variable_get(:@journal)
      expect(journal_payload.date).to eq(Date.new(2026, 2, 5))
    end
  end

  describe "GET #show" do
    it "loads data from fixture-backed journal via factory fallback" do
      journal = create(:journal)

      get :show, params: { date: "2026-02-05" }

      expect(response).to have_http_status(:ok)
      journal_payload = controller.instance_variable_get(:@journal)
      meals_payload = controller.instance_variable_get(:@meals)
      exercises_payload = controller.instance_variable_get(:@exercises)
      expect(journal.id).to eq(3001)
      expect(journal_payload.id).to eq(3001)
      expect(journal_payload.date).to eq(Date.new(2026, 2, 5))
      expect(meals_payload.size).to eq(1)
      expect(exercises_payload.size).to eq(1)
    end

    it "returns empty payload when journal does not exist for date" do
      get :show, params: { date: "2026-02-06" }

      expect(response).to have_http_status(:ok)
      journal_payload = controller.instance_variable_get(:@journal)
      meals_payload = controller.instance_variable_get(:@meals)
      exercises_payload = controller.instance_variable_get(:@exercises)
      expect(journal_payload).to be_a(Journal)
      expect(journal_payload.id).to be_nil
      expect(journal_payload.date).to eq(Date.new(2026, 2, 6))
      expect(meals_payload).to be_empty
      expect(exercises_payload).to be_empty
    end

    it "redirects to /journals/today when date is in the future" do
      get :show, params: { date: "2030-01-01" }

      expect(response).to redirect_to("/journals/today")
    end

    it "does not leak journal data from another user's patient" do
      other_user = create(:user)
      other_patient = create(:patient, user: other_user)
      other_journal = Journal.create!(patient: other_patient, date: Date.new(2026, 2, 5))
      Meal.create!(
        journal: other_journal,
        meal_type: "lunch",
        description: "Other user meal",
        calories: 450,
        status: "confirmed"
      )

      get :show, params: { date: "2026-02-05" }

      journal_payload = controller.instance_variable_get(:@journal)
      meals_payload = controller.instance_variable_get(:@meals)
      expect(journal_payload.id).to eq(3001)
      expect(meals_payload.size).to eq(1)
    end

    it "shows delete actions for pending meals and exercises" do
      journal = create(:journal)
      pending_meal = Meal.create!(
        journal: journal,
        meal_type: "lunch",
        description: "Refeição pendente",
        status: "pending_patient"
      )
      pending_exercise = Exercise.create!(
        journal: journal,
        description: "Exercício pendente",
        status: "pending_llm"
      )

      get :show, params: { date: "2026-02-05" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(href="/journals/2026-02-05/meals/#{pending_meal.id}"))
      expect(response.body).to include(%(href="/journals/2026-02-05/exercises/#{pending_exercise.id}"))
      expect(response.body).to include("data-turbo-method=\"delete\"")
      expect(response.body).to include("data-turbo-confirm=")
    end

    it "uses effective_calories_burned in daily summary" do
      journal = create(:journal)
      Exercise.create!(
        journal: journal,
        description: "Bike",
        calories: 432,
        status: "confirmed"
      )

      get :show, params: { date: "2026-02-05" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(journal.effective_calories_burned.to_s)
    end

    it "does not render close day button in daily summary" do
      get :show, params: { date: "2026-02-05" }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(close_journal_path(date: "2026-02-05"))
    end
  end

  describe "authorization without patient" do
    it "returns forbidden for authenticated user without patient record" do
      user_without_patient = create(:user)
      session[:user_id] = user_without_patient.id

      get :show, params: { date: "2026-02-05" }

      expect(response).to have_http_status(:forbidden)
    end
  end
end
