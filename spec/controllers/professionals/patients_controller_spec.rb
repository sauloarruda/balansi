require "rails_helper"

RSpec.describe Professionals::PatientsController, type: :controller do
  include ActiveSupport::Testing::TimeHelpers
  render_views

  let(:user) { create(:user) }
  let!(:professional) { create(:professional, user: user) }

  before do
    session[:user_id] = user.id
  end

  describe "GET #index" do
    it "returns success and renders patient list" do
      get :index, params: {}

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("professional.patients.index.title"))
    end

    it "shows empty message when no linked patients" do
      get :index, params: {}

      expect(response.body).to include(I18n.t("professional.patients.index.empty"))
    end

    it "lists owned and shared patients with correct badges" do
      owned = create(:patient, professional: professional)
      other_pro = create(:professional)
      shared = create(:patient, professional: other_pro)
      create(:patient_professional_access, patient: shared, professional: professional, granted_by_patient_user: shared.user)

      get :index, params: {}

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(owned.user.name)
      expect(response.body).to include(shared.user.name)
      expect(response.body).to include(I18n.t("professional.patients.index.owner_badge"))
      expect(response.body).to include(I18n.t("professional.patients.index.shared_badge"))
    end
  end

  describe "GET #show" do
    let(:patient) { create(:patient, professional: professional) }

    it "returns success and shows profile" do
      get :show, params: { id: patient.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(patient.user.name)
    end

    it "returns forbidden when professional cannot access patient" do
      other_patient = create(:patient)

      get :show, params: { id: other_patient.id }

      expect(response).to have_http_status(:forbidden)
    end
  end
end
