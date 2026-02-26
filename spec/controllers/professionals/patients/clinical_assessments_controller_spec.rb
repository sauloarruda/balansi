require "rails_helper"

RSpec.describe Professionals::Patients::ClinicalAssessmentsController, type: :controller do
  include ActiveSupport::Testing::TimeHelpers
  render_views

  let(:user) { create(:user) }
  let!(:professional) { create(:professional, user: user) }

  before do
    session[:user_id] = user.id
  end

  describe "GET #edit" do
    let(:patient) { create(:patient, professional: professional) }

    it "returns success for owner" do
      get :edit, params: { patient_id: patient.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("professional.patients.clinical_assessment.edit.title"))
    end

    it "returns forbidden for shared professional" do
      other_pro = create(:professional)
      shared_patient = create(:patient, professional: other_pro)
      create(:patient_professional_access, patient: shared_patient, professional: professional, granted_by_patient_user: shared_patient.user)

      get :edit, params: { patient_id: shared_patient.id }

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH #update" do
    let(:patient) { create(:patient, professional: professional) }

    it "updates clinical assessment and clinical_assessment_last_updated_at for owner" do
      travel_to(Time.zone.local(2026, 3, 1, 10, 0, 0)) do
        patch :update, params: {
          patient_id: patient.id,
          patient: {
            daily_calorie_goal: 2200,
            bmr: 1650,
            steps_goal: 8000,
            hydration_goal: 2500
          }
        }
      end

      expect(response).to redirect_to(professional_patient_path(patient))
      expect(flash[:notice]).to eq(I18n.t("professional.patients.clinical_assessment.update.success"))

      patient.reload
      expect(patient.daily_calorie_goal).to eq(2200)
      expect(patient.bmr).to eq(1650)
      expect(patient.steps_goal).to eq(8000)
      expect(patient.hydration_goal).to eq(2500)
      expect(patient.clinical_assessment_last_updated_at).to eq(Time.zone.local(2026, 3, 1, 10, 0, 0))
    end

    it "returns forbidden for shared professional" do
      other_pro = create(:professional)
      shared_patient = create(:patient, professional: other_pro)
      create(:patient_professional_access, patient: shared_patient, professional: professional, granted_by_patient_user: shared_patient.user)

      patch :update, params: {
        patient_id: shared_patient.id,
        patient: { daily_calorie_goal: 2000 }
      }

      expect(response).to have_http_status(:forbidden)
      expect(shared_patient.reload.daily_calorie_goal).not_to eq(2000)
    end
  end
end
