require "rails_helper"

RSpec.describe "Journal meal flow", type: :request do
  let(:user) { create(:user, language: "pt") }
  let!(:patient) { create(:patient, user: user) }

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
    client = instance_double(Journal::MealAnalysisClient)
    allow(client).to receive(:analyze).and_return(
      {
        p: 25,
        c: 40,
        f: 12,
        cal: 380,
        gw: 300,
        cmt: "Resposta mockada.",
        feel: 1
      }
    )
    allow_any_instance_of(Journal::AnalyzeMealInteraction).to receive(:llm_client).and_return(client)
  end

  it "creates, confirms and reprocesses a meal" do
    expect do
      post journal_meals_path(journal_date: "2026-02-05"), params: {
        meal: {
          date: "2026-02-05",
          meal_type: "lunch",
          description: "Frango com arroz e salada"
        }
      }
    end.to change(Meal, :count).by(1)

    meal = Meal.last
    expect(response).to redirect_to(journal_meal_path(journal_date: "2026-02-05", id: meal.id))
    expect(meal.reload.status.to_s).to eq("pending_patient")

    patch journal_meal_path(journal_date: "2026-02-05", id: meal.id), params: {
      confirm: "1",
      meal: {
        calories: 420,
        proteins: 30,
        carbs: 45,
        fats: 12,
        gram_weight: 350
      }
    }

    expect(response).to redirect_to(journal_path(date: "2026-02-05"))
    expect(meal.reload.status.to_s).to eq("confirmed")

    patch journal_meal_path(journal_date: "2026-02-05", id: meal.id), params: {
      reprocess: "1",
      meal: {
        meal_type: meal.meal_type,
        description: "Peixe grelhado com legumes"
      }
    }

    expect(response).to redirect_to(journal_meal_path(journal_date: "2026-02-05", id: meal.id))
    expect(meal.reload.status.to_s).to eq("pending_patient")
  end
end
