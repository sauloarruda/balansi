require "rails_helper"

RSpec.describe "Patient recipes", type: :request do
  let(:user) { create(:user) }
  let!(:patient) { create(:patient, user: user) }

  before do
    host! "localhost"
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
  end

  it "renders a recipe navigation entry in the application layout" do
    get patient_recipes_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(href="/patient/recipes"))
    expect(response.body).to include(I18n.t("patient.recipes.navigation.title"))
  end

  context "when the patient user also has a professional profile" do
    let!(:professional) { create(:professional, user: user) }

    it "still renders the recipe navigation entry" do
      get patient_recipes_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(href="/patient/recipes"))
      expect(response.body).to include(I18n.t("patient.recipes.navigation.title"))
    end

    it "renders the professional patients top button as an icon" do
      get patient_recipes_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(href="#{professional_patients_path}"))
      expect(response.body).to include(%(aria-label="#{I18n.t("professional.patients.index.title")}"))
      expect(response.body).to include("<svg")
    end
  end
end
