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

    it "renders close day button for open journal" do
      create(:journal)

      get :show, params: { date: "2026-02-05" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(close_journal_path(date: "2026-02-05"))
    end

    it "does not render close day button for journal closed more than 2 days ago" do
      journal = create(:journal)
      journal.update!(closed_at: 3.days.ago)

      get :show, params: { date: "2026-02-05" }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(close_journal_path(date: "2026-02-05"))
    end

    it "does not render close day button for unsaved (new) journal" do
      get :show, params: { date: "2026-02-06" }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(close_journal_path(date: "2026-02-06"))
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

  describe "professional redirect" do
    it "redirects to professional patients when user has professional and no patient" do
      user = create(:user)
      create(:professional, user: user)
      session[:user_id] = user.id

      get :show, params: { date: "2026-02-05" }

      expect(response).to redirect_to(professional_patients_path)
    end
  end

  describe "profile completion gate" do
    it "redirects to profile completion when patient profile is incomplete" do
      patient = Patient.find(2001)
      patient.update!(
        gender: nil,
        birth_date: nil,
        weight_kg: nil,
        height_cm: nil,
        phone_e164: nil,
        profile_completed_at: nil
      )

      get :show, params: { date: "2026-02-05" }

      expect(response).to redirect_to(patient_personal_profile_path)
    end
  end

  describe "PATCH #close" do
    let(:journal) { create(:journal) }

    before { journal }

    def mock_scoring_success
      errors = ActiveModel::Errors.new(Journal.new)
      result = instance_double(ActiveInteraction::Base, valid?: true, errors: errors, result: journal)
      allow(Journal::ScoreDailyJournalInteraction).to receive(:run).and_return(result)
    end

    def mock_scoring_failure
      errors = double(full_messages: [ "Não foi possível calcular sua pontuação agora" ])
      result = instance_double(ActiveInteraction::Base, valid?: false, errors: errors, result: nil)
      allow(Journal::ScoreDailyJournalInteraction).to receive(:run).and_return(result)
    end

    it "closes the journal and redirects with success notice when scoring succeeds" do
      mock_scoring_success

      patch :close, params: {
        date: "2026-02-05",
        feeling_today: "good",
        sleep_quality: "excellent",
        hydration_quality: "good",
        steps_count: 8000,
        daily_note: "Great day"
      }

      journal.reload
      expect(journal.closed_at).not_to be_nil
      expect(journal.feeling_today.to_s).to eq("good")
      expect(journal.sleep_quality.to_s).to eq("excellent")
      expect(journal.hydration_quality.to_s).to eq("good")
      expect(journal.steps_count).to eq(8000)
      expect(journal.daily_note).to eq("Great day")
      expect(response).to redirect_to(journal_path(date: "2026-02-05"))
      expect(flash[:notice]).to include("fechado com sucesso")
    end

    it "closes the journal with alert when scoring fails" do
      mock_scoring_failure

      patch :close, params: {
        date: "2026-02-05",
        feeling_today: "ok",
        sleep_quality: "good",
        hydration_quality: "poor",
        steps_count: 4000
      }

      journal.reload
      expect(journal.closed_at).not_to be_nil
      expect(response).to redirect_to(journal_path(date: "2026-02-05"))
      expect(flash[:alert]).to include("pontuação")
    end

    it "deletes pending entries on closure" do
      mock_scoring_success
      pending_meal = Meal.create!(journal: journal, meal_type: "snack", description: "Pending snack", status: "pending_patient")
      pending_exercise = Exercise.create!(journal: journal, description: "Pending run", status: "pending_llm")
      confirmed_meal = Meal.create!(journal: journal, meal_type: "lunch", description: "Confirmed lunch", calories: 500, status: "confirmed")

      patch :close, params: { date: "2026-02-05", feeling_today: "good", sleep_quality: "good", hydration_quality: "good", steps_count: 5000 }

      expect(Meal.exists?(pending_meal.id)).to be false
      expect(Exercise.exists?(pending_exercise.id)).to be false
      expect(Meal.exists?(confirmed_meal.id)).to be true
    end

    it "calculates and stores totals on closure" do
      mock_scoring_success
      Meal.create!(journal: journal, meal_type: "breakfast", description: "Oats", calories: 400, status: "confirmed")
      Meal.create!(journal: journal, meal_type: "lunch", description: "Chicken", calories: 600, status: "confirmed")
      patient = Patient.find(2001)
      patient.update!(bmr: 1800)

      patch :close, params: { date: "2026-02-05", feeling_today: "good", sleep_quality: "good", hydration_quality: "good", steps_count: 6000 }

      journal.reload
      expect(journal.calories_consumed).to eq(1000)
      expect(journal.calories_burned).to eq(1800)
    end

    it "redirects with not_found when journal does not exist" do
      patch :close, params: {
        date: "2026-01-01",
        feeling_today: "good",
        sleep_quality: "good",
        hydration_quality: "good",
        steps_count: 5000
      }

      expect(response).to redirect_to(journal_path(date: "2026-01-01"))
      expect(flash[:alert]).to be_present
    end

    it "redirects with read_only alert when journal is closed and past editable window" do
      journal.update!(closed_at: 3.days.ago)

      patch :close, params: {
        date: "2026-02-05",
        feeling_today: "good",
        sleep_quality: "good",
        hydration_quality: "good",
        steps_count: 5000
      }

      expect(response).to redirect_to(journal_path(date: "2026-02-05"))
      expect(flash[:alert]).to include("editado")
    end
  end
end
