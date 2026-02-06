require "rails_helper"

RSpec.describe "Journal exercise flow", type: :request do
  let(:user) { create(:user, language: "pt") }
  let!(:patient) { create(:patient, user: user) }

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
    client = instance_double(Journal::ExerciseAnalysisClient)
    allow(client).to receive(:analyze).and_return(
      {
        d: 30,
        cal: 250,
        n: 0,
        sd: "Corrida moderada por 30 minutos"
      }
    )
    allow_any_instance_of(Journal::AnalyzeExerciseInteraction).to receive(:llm_client).and_return(client)
  end

  it "creates, confirms and reprocesses an exercise" do
    expect do
      post journal_exercises_path(journal_date: "2026-02-05"), params: {
        exercise: {
          date: "2026-02-05",
          description: "Corrida moderada de 30 minutos"
        }
      }
    end.to change(Exercise, :count).by(1)

    exercise = Exercise.last
    expect(response).to redirect_to(journal_exercise_path(journal_date: "2026-02-05", id: exercise.id))
    expect(exercise.reload.status.to_s).to eq("pending_patient")

    patch journal_exercise_path(journal_date: "2026-02-05", id: exercise.id), params: {
      confirm: "1",
      exercise: {
        duration: 35,
        calories: 280,
        neat: 0,
        structured_description: "Corrida moderada por 35 minutos"
      }
    }

    expect(response).to redirect_to(journal_path(date: "2026-02-05"))
    expect(exercise.reload.status.to_s).to eq("confirmed")

    patch journal_exercise_path(journal_date: "2026-02-05", id: exercise.id), params: {
      reprocess: "1",
      exercise: {
        description: "Bike moderada por 25 minutos"
      }
    }

    expect(response).to redirect_to(journal_exercise_path(journal_date: "2026-02-05", id: exercise.id))
    expect(exercise.reload.status.to_s).to eq("pending_patient")
  end
end
