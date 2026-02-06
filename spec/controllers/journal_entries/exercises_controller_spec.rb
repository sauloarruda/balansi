require "rails_helper"

RSpec.describe JournalEntries::ExercisesController, type: :controller do
  render_views

  before do
    create(:journal)
    session[:user_id] = User.find(1001).id
  end

  let(:patient) { Patient.find(2001) }
  let(:journal) { patient.journals.find_by!(date: Date.new(2026, 2, 5)) }

  describe "GET #new" do
    it "renders new exercise form" do
      get :new, params: { journal_date: "2026-02-05" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("exercise[description]")
    end
  end

  describe "POST #create" do
    it "creates exercise and auto-creates journal when needed" do
      interaction_errors = ActiveModel::Errors.new(Exercise.new)
      interaction_result = instance_double(ActiveInteraction::Base, valid?: true, errors: interaction_errors)
      allow(Journal::AnalyzeExerciseInteraction).to receive(:run).and_return(interaction_result)

      expect do
        post :create, params: {
          journal_date: "2026-02-06",
          exercise: {
            date: "2026-02-06",
            description: "Corrida moderada por 30 minutos"
          }
        }
      end.to change(Exercise, :count).by(1)

      created_journal = patient.journals.find_by(date: Date.new(2026, 2, 6))
      expect(created_journal).to be_present
      expect(response).to redirect_to(journal_exercise_path(journal_date: "2026-02-06", id: Exercise.last.id))
    end

    it "shows error when analysis fails" do
      error_messages = double(full_messages: [ "LLM indisponível" ])
      interaction_result = instance_double(ActiveInteraction::Base, valid?: false, errors: error_messages)
      allow(Journal::AnalyzeExerciseInteraction).to receive(:run).and_return(interaction_result)

      post :create, params: {
        journal_date: "2026-02-06",
        exercise: {
          date: "2026-02-06",
          description: "Corrida moderada por 30 minutos"
        }
      }

      expect(flash[:error]).to include("LLM indisponível")
      expect(response).to redirect_to(journal_exercise_path(journal_date: "2026-02-06", id: Exercise.last.id))
    end
  end

  describe "PATCH #update" do
    let!(:exercise) { Exercise.create!(journal: journal, description: "Corrida moderada", status: "pending_patient") }

    it "confirms an exercise" do
      patch :update, params: {
        journal_date: "2026-02-05",
        id: exercise.id,
        confirm: "1",
        exercise: {
          duration: 30,
          calories: 250,
          neat: 10,
          structured_description: "Corrida moderada por 30 minutos"
        }
      }

      expect(response).to redirect_to(journal_path(date: "2026-02-05"))
      expect(exercise.reload.status.to_s).to eq("confirmed")
      expect(exercise.duration).to eq(30)
    end

    it "reprocesses an exercise" do
      interaction_errors = ActiveModel::Errors.new(Exercise.new)
      interaction_result = instance_double(ActiveInteraction::Base, valid?: true, errors: interaction_errors)
      allow(Journal::AnalyzeExerciseInteraction).to receive(:run) do
        Exercise.find(exercise.id).update!(status: :pending_patient)
        interaction_result
      end

      patch :update, params: {
        journal_date: "2026-02-05",
        id: exercise.id,
        reprocess: "1",
        exercise: {
          description: "Bike ergométrica moderada"
        }
      }

      expect(response).to redirect_to(journal_exercise_path(journal_date: "2026-02-05", id: exercise.id))
      expect(exercise.reload.status.to_s).to eq("pending_patient")
      expect(Journal::AnalyzeExerciseInteraction).to have_received(:run)
    end
  end

  describe "DELETE #destroy" do
    it "deletes exercise" do
      exercise = Exercise.create!(journal: journal, description: "Corrida moderada", status: "confirmed")

      expect do
        delete :destroy, params: { journal_date: "2026-02-05", id: exercise.id }
      end.to change(Exercise, :count).by(-1)

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
