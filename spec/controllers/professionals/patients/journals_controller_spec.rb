require "rails_helper"

RSpec.describe Professionals::Patients::JournalsController, type: :controller do
  render_views

  let(:user) { create(:user) }
  let!(:professional) { create(:professional, user: user) }

  before do
    session[:user_id] = user.id
  end

  describe "GET #show" do
    it "returns success for owner" do
      patient = create(:patient, professional: professional)

      get :show, params: { id: patient.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("journals.show.breadcrumb_daily_journal"))
      expect(response.body).to include("data-date-navigator-url-template-value=\"#{journal_professional_patient_path(patient, date: '__DATE__')}\"")
    end

    it "returns success for shared professional" do
      other_professional = create(:professional)
      shared_patient = create(:patient, professional: other_professional)
      create(
        :patient_professional_access,
        patient: shared_patient,
        professional: professional,
        granted_by_patient_user: shared_patient.user
      )

      get :show, params: { id: shared_patient.id }

      expect(response).to have_http_status(:ok)
    end

    it "renders referenced recipe details as read-only for an authorized professional" do
      patient = create(:patient, professional: professional)
      journal = create(:journal, patient: patient, date: Date.new(2026, 2, 6))
      recipe = create(:recipe, patient: patient, name: "Chicken bowl", calories: 400, proteins: 30, carbs: 45, fats: 12)
      meal = create(
        :meal,
        journal: journal,
        meal_type: "lunch",
        description: "Lunch with @[Chicken bowl](recipe:#{recipe.id})",
        status: "confirmed",
        calories: 400,
        proteins: 30,
        carbs: 45,
        fats: 12,
        gram_weight: 200
      )
      create(:meal_recipe_reference, meal: meal, recipe: recipe)

      get :show, params: { id: patient.id, date: "2026-02-06" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Chicken bowl")
      expect(response.body).to include("400")
      expect(response.body).to include(I18n.t("defaults.kcal"))
      expect(response.body).to include("macro-ring")
      expect(response.body).to include("data-controller=\"popover-tooltip\"")
      expect(response.body).not_to include(patient_recipe_path(recipe))
    end

    it "returns forbidden when professional has no access" do
      patient = create(:patient)

      get :show, params: { id: patient.id }

      expect(response).to have_http_status(:forbidden)
    end

    it "does not render recipe details when professional has no patient access" do
      patient = create(:patient)
      journal = create(:journal, patient: patient, date: Date.new(2026, 2, 6))
      recipe = create(:recipe, patient: patient, name: "Private recipe")
      meal = create(:meal, journal: journal, description: "Meal with @[Private recipe](recipe:#{recipe.id})")
      create(:meal_recipe_reference, meal: meal, recipe: recipe)

      get :show, params: { id: patient.id, date: "2026-02-06" }

      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to include("Private recipe")
    end

    it "returns not found when patient does not exist" do
      get :show, params: { id: 999_999 }

      expect(response).to have_http_status(:not_found)
    end
  end
end
