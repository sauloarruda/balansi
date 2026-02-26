require "rails_helper"

RSpec.describe Professionals::Patients::PersonalProfilesController, type: :controller do
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
      expect(response.body).to include(I18n.t("professional.patients.personal_profile.edit.title"))
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
    let(:patient) { create(:patient, professional: professional, gender: "female", weight_kg: 70, height_cm: 170, phone_e164: "+5511999999999") }

    it "updates personal profile and profile_last_updated_at for owner" do
      travel_to(Time.zone.local(2026, 3, 1, 10, 0, 0)) do
        patch :update, params: {
          patient_id: patient.id,
          patient: {
            gender: "male",
            birth_date: Date.new(1991, 3, 10).strftime(I18n.t("patient_personal_profile.show.birth_date_format")),
            weight_kg: 78.5,
            height_cm: 182.0,
            phone_country: "BR",
            phone_national_number: "(11) 98888-7777"
          }
        }
      end

      expect(response).to redirect_to(professional_patient_path(patient))
      expect(flash[:notice]).to eq(I18n.t("professional.patients.personal_profile.update.success"))

      patient.reload
      expect(patient.gender).to eq("male")
      expect(patient.weight_kg).to eq(78.5)
      expect(patient.height_cm).to eq(182.0)
      expect(patient.phone_e164).to eq("+5511988887777")
      expect(patient.profile_last_updated_at).to be_present
    end

    it "returns forbidden for shared professional" do
      other_pro = create(:professional)
      shared_patient = create(:patient, professional: other_pro)
      create(:patient_professional_access, patient: shared_patient, professional: professional, granted_by_patient_user: shared_patient.user)

      patch :update, params: {
        patient_id: shared_patient.id,
        patient: { gender: "male", weight_kg: 80 }
      }

      expect(response).to have_http_status(:forbidden)
    end
  end
end
