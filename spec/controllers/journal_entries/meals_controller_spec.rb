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
      expect(response.body).to include('data-recipe-mentions-search-url-value="/patient/recipes/search"')
    end
  end

  describe "GET #edit" do
    it "renders the recipe mention editor with the saved description" do
      meal = Meal.create!(
        journal: journal,
        meal_type: "lunch",
        description: "Comi @[Carne com legumes](recipe:6)",
        status: "pending_patient"
      )

      get :edit, params: { journal_date: "2026-02-05", id: meal.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-recipe-mentions-target="editor"')
      expect(response.body).to include('value="Comi @[Carne com legumes](recipe:6)"')
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

    it "creates recipe reference snapshots from owned recipe mentions" do
      recipe = create(:recipe, patient: patient, name: "Carne com legumes", calories: 510)
      interaction_errors = ActiveModel::Errors.new(Meal.new)
      interaction_result = instance_double(ActiveInteraction::Base, valid?: true, errors: interaction_errors)
      allow(Journal::AnalyzeMealInteraction).to receive(:run).and_return(interaction_result)

      post :create, params: {
        journal_date: "2026-02-06",
        meal: {
          date: "2026-02-06",
          meal_type: "dinner",
          description: "Jantar com @[Carne com legumes](recipe:#{recipe.id})"
        }
      }

      reference = Meal.last.meal_recipe_references.sole
      expect(reference.recipe).to eq(recipe)
      expect(reference.recipe_name).to eq("Carne com legumes")
      expect(reference.calories_per_portion).to eq(510)
    end
  end

  describe "PATCH #update" do
    let!(:meal) do
      Meal.create!(
        journal: journal,
        meal_type: "lunch",
        description: "Arroz e feijão",
        status: "pending_patient",
        calories: 430,
        proteins: 18,
        carbs: 54,
        fats: 10,
        gram_weight: 300
      )
    end

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

    it "saves meal edits without confirming" do
      patch :update, params: {
        journal_date: "2026-02-05",
        id: meal.id,
        meal: {
          calories: 470,
          proteins: 22,
          carbs: 58,
          fats: 11,
          gram_weight: 340
        }
      }

      expect(response).to redirect_to(journal_path(date: "2026-02-05"))
      expect(meal.reload.status.to_s).to eq("pending_patient")
      expect(meal.calories).to eq(470)
      expect(meal.proteins).to eq(22)
      expect(meal.carbs).to eq(58)
      expect(meal.fats).to eq(11)
      expect(meal.gram_weight).to eq(340)
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
          description: "Frango grelhado",
          calories: 999,
          proteins: 999,
          carbs: 999,
          fats: 999,
          gram_weight: 999
        }
      }

      expect(response).to redirect_to(journal_meal_path(journal_date: "2026-02-05", id: meal.id))
      expect(meal.reload.status.to_s).to eq("pending_patient")
      expect(meal.meal_type).to eq("dinner")
      expect(meal.calories).to eq(430)
      expect(meal.proteins).to eq(18)
      expect(meal.carbs).to eq(54)
      expect(meal.fats).to eq(10)
      expect(meal.gram_weight).to eq(300)
      expect(Journal::AnalyzeMealInteraction).to have_received(:run)
    end

    it "refreshes recipe references when reprocessing" do
      old_recipe = create(:recipe, patient: patient, name: "Arroz antigo")
      new_recipe = create(:recipe, patient: patient, name: "Frango novo")
      create(:meal_recipe_reference, meal: meal, recipe: old_recipe)
      interaction_errors = ActiveModel::Errors.new(Meal.new)
      interaction_result = instance_double(ActiveInteraction::Base, valid?: true, errors: interaction_errors)
      allow(Journal::AnalyzeMealInteraction).to receive(:run).and_return(interaction_result)

      patch :update, params: {
        journal_date: "2026-02-05",
        id: meal.id,
        reprocess: "1",
        meal: {
          meal_type: "dinner",
          description: "Jantar com @[Frango novo](recipe:#{new_recipe.id})"
        }
      }

      reference = meal.reload.meal_recipe_references.sole
      expect(reference.recipe).to eq(new_recipe)
      expect(reference.recipe_name).to eq("Frango novo")
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
