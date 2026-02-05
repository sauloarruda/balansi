require "rails_helper"

RSpec.describe JournalEntries::MealsController, type: :controller do
  render_views

  before do
    create(:journal)
    session[:user_id] = User.find(1001).id
  end

  let(:patient) { Patient.find(2001) }
  let(:journal) { patient.journals.find_by!(date: Date.new(2026, 2, 5)) }

  describe "GET #new" do
    it "renders new meal form" do
      get :new, params: { journal_date: "2026-02-05", meal_type: "lunch" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("meal[meal_type]")
      expect(response.body).to include("lunch")
    end
  end

  describe "POST #create" do
    it "creates meal and auto-creates journal when needed" do
      interaction_errors = ActiveModel::Errors.new(Meal.new)
      interaction_result = instance_double(ActiveInteraction::Base, valid?: true, errors: interaction_errors)
      allow(Journal::AnalyzeMealInteraction).to receive(:run).and_return(interaction_result)

      expect do
        post :create, params: {
          journal_date: "2026-02-06",
          meal: {
            date: "2026-02-06",
            meal_type: "dinner",
            description: "Peixe com salada"
          }
        }
      end.to change(Meal, :count).by(1)

      created_journal = patient.journals.find_by(date: Date.new(2026, 2, 6))
      expect(created_journal).to be_present
      expect(response).to redirect_to(journal_meal_path(journal_date: "2026-02-06", id: Meal.last.id))
    end

    it "shows error when analysis fails" do
      error_messages = double(full_messages: [ "LLM indisponível" ])
      interaction_result = instance_double(ActiveInteraction::Base, valid?: false, errors: error_messages)
      allow(Journal::AnalyzeMealInteraction).to receive(:run).and_return(interaction_result)

      post :create, params: {
        journal_date: "2026-02-06",
        meal: {
          date: "2026-02-06",
          meal_type: "dinner",
          description: "Peixe com salada"
        }
      }

      expect(flash[:error]).to include("LLM indisponível")
      expect(response).to redirect_to(journal_meal_path(journal_date: "2026-02-06", id: Meal.last.id))
    end
  end

  describe "PATCH #update" do
    let!(:meal) { Meal.create!(journal: journal, meal_type: "lunch", description: "Arroz e feijão", status: "pending_patient") }

    it "confirms a meal" do
      patch :update, params: {
        journal_date: "2026-02-05",
        id: meal.id,
        confirm: "1",
        meal: {
          calories: 450,
          proteins: 20,
          carbs: 55,
          fats: 12,
          gram_weight: 320
        }
      }

      expect(response).to redirect_to(journal_path(date: "2026-02-05"))
      expect(meal.reload.status.to_s).to eq("confirmed")
      expect(meal.calories).to eq(450)
    end

    it "reprocesses a meal" do
      interaction_errors = ActiveModel::Errors.new(Meal.new)
      interaction_result = instance_double(ActiveInteraction::Base, valid?: true, errors: interaction_errors)
      allow(Journal::AnalyzeMealInteraction).to receive(:run) do
        Meal.find(meal.id).update!(status: :pending_patient)
        interaction_result
      end

      patch :update, params: {
        journal_date: "2026-02-05",
        id: meal.id,
        reprocess: "1",
        meal: {
          meal_type: "dinner",
          description: "Frango grelhado"
        }
      }

      expect(response).to redirect_to(journal_meal_path(journal_date: "2026-02-05", id: meal.id))
      expect(meal.reload.status.to_s).to eq("pending_patient")
      expect(Journal::AnalyzeMealInteraction).to have_received(:run)
    end
  end

  describe "DELETE #destroy" do
    it "deletes meal" do
      meal = Meal.create!(journal: journal, meal_type: "lunch", description: "Arroz e feijão", status: "confirmed")

      expect do
        delete :destroy, params: { journal_date: "2026-02-05", id: meal.id }
      end.to change(Meal, :count).by(-1)

      expect(response).to redirect_to(journal_path(date: "2026-02-05"))
    end
  end

  describe "authorization without patient" do
    it "returns forbidden for authenticated user without patient record" do
      user_without_patient = create(:user)
      session[:user_id] = user_without_patient.id

      get :new, params: { journal_date: "2026-02-05" }

      expect(response).to have_http_status(:forbidden)
    end
  end
end
