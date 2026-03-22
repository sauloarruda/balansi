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

    it "returns forbidden when professional has no access" do
      patient = create(:patient)

      get :show, params: { id: patient.id }

      expect(response).to have_http_status(:forbidden)
    end

    it "returns not found when patient does not exist" do
      get :show, params: { id: 999_999 }

      expect(response).to have_http_status(:not_found)
    end
  end
end
