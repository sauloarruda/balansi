require "rails_helper"

RSpec.describe "Journal close flow", type: :request do
  let(:user) { create(:user, language: "pt") }
  let!(:patient) { create(:patient, user: user, bmr: 1800, daily_calorie_goal: 2200, steps_goal: 8000, hydration_goal: 2000) }
  let!(:journal) { Journal.create!(patient: patient, date: Date.new(2026, 2, 5)) }

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)

    errors = ActiveModel::Errors.new(Journal.new)
    scoring_result = instance_double(ActiveInteraction::Base, valid?: true, errors: errors, result: journal)
    allow(Journal::ScoreDailyJournalInteraction).to receive(:run).and_return(scoring_result)
  end

  it "closes a day, cleans up pending entries, stores totals, and redirects" do
    Meal.create!(journal: journal, meal_type: "breakfast", description: "Oats", calories: 350, proteins: 12, carbs: 60, fats: 5, status: "confirmed")
    Meal.create!(journal: journal, meal_type: "snack", description: "Cookies", status: "pending_patient")
    Exercise.create!(journal: journal, description: "Bike ride", calories: 300, status: "confirmed")
    Exercise.create!(journal: journal, description: "Stretching", status: "pending_llm")

    patch close_journal_path(date: "2026-02-05"), params: {
      feeling_today: "good",
      sleep_quality: "excellent",
      hydration_quality: "good",
      steps_count: 9000,
      daily_note: "Felt great today"
    }

    expect(response).to redirect_to(journal_path(date: "2026-02-05"))

    journal.reload
    expect(journal.closed_at).not_to be_nil
    expect(journal.feeling_today.to_s).to eq("good")
    expect(journal.sleep_quality.to_s).to eq("excellent")
    expect(journal.steps_count).to eq(9000)
    expect(journal.daily_note).to eq("Felt great today")
    expect(journal.calories_consumed).to eq(350)
    expect(journal.calories_burned).to eq(2100)

    expect(Meal.where(journal: journal, status: "pending_patient").count).to eq(0)
    expect(Exercise.where(journal: journal, status: "pending_llm").count).to eq(0)
    expect(Meal.where(journal: journal, status: "confirmed").count).to eq(1)
    expect(Exercise.where(journal: journal, status: "confirmed").count).to eq(1)
  end

  it "returns journal not found when journal does not exist for that date" do
    patch close_journal_path(date: "2025-01-01"), params: {
      feeling_today: "ok",
      sleep_quality: "good",
      hydration_quality: "poor",
      steps_count: 3000
    }

    expect(response).to redirect_to(journal_path(date: "2025-01-01"))
    follow_redirect!
    expect(response.body).to include("não encontrado")
  end

  it "shows success flash after scoring" do
    patch close_journal_path(date: "2026-02-05"), params: {
      feeling_today: "good",
      sleep_quality: "good",
      hydration_quality: "good",
      steps_count: 7000
    }

    follow_redirect!
    expect(response.body).to include("fechado com sucesso")
  end
end
