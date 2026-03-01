require "rails_helper"

RSpec.describe Patients::ProfessionalAccessesController, type: :controller do
  render_views

  let(:patient_user) { create(:user) }
  let(:professional) { create(:professional) }
  let!(:patient) { create(:patient, user: patient_user, professional: professional) }

  before { session[:user_id] = patient_user.id }

  describe "GET #index" do
    it "returns success and renders the sharing page" do
      get :index

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("patient.professional_accesses.index.title"))
    end

    it "shows existing shared accesses" do
      other_pro = create(:professional)
      create(:patient_professional_access, patient: patient, professional: other_pro, granted_by_patient_user: patient_user)

      get :index

      expect(response.body).to include(other_pro.user.name)
    end

    it "shows no accesses message when none exist" do
      get :index

      expect(response.body).to include(I18n.t("patient.professional_accesses.index.no_accesses"))
    end
  end

  describe "POST #create" do
    let(:other_pro_user) { create(:user) }
    let!(:other_pro) { create(:professional, user: other_pro_user) }

    context "when the email belongs to a valid professional" do
      it "creates the access and redirects with success notice" do
        post :create, params: { professional_access: { professional_email: other_pro_user.email } }

        expect(response).to redirect_to(patient_professional_accesses_path)
        expect(flash[:notice]).to eq(I18n.t("patient.professional_accesses.messages.shared_success"))
        expect(PatientProfessionalAccess.exists?(patient: patient, professional: other_pro)).to be true
      end

      it "preserves existing owner access after sharing" do
        post :create, params: { professional_access: { professional_email: other_pro_user.email } }

        patient.reload
        expect(patient.professional_id).to eq(professional.id)
      end
    end

    context "when the professional is not found" do
      it "re-renders the form with error" do
        post :create, params: { professional_access: { professional_email: "unknown@example.com" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include(I18n.t("patient.professional_accesses.errors.professional_not_found"))
      end
    end

    context "when sharing with the owner professional" do
      it "re-renders the form with error" do
        post :create, params: { professional_access: { professional_email: professional.user.email } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include(I18n.t("patient.professional_accesses.errors.already_owner"))
      end
    end

    context "when the professional already has shared access" do
      let!(:other_pro) { create(:professional, user: other_pro_user) }

      before do
        create(:patient_professional_access, patient: patient, professional: other_pro, granted_by_patient_user: patient_user)
      end

      it "re-renders the form with error" do
        post :create, params: { professional_access: { professional_email: other_pro_user.email } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include(I18n.t("patient.professional_accesses.errors.already_shared"))
      end
    end
  end

  describe "DELETE #destroy" do
    let(:other_pro) { create(:professional) }
    let!(:access) do
      create(:patient_professional_access, patient: patient, professional: other_pro, granted_by_patient_user: patient_user)
    end

    context "when the access belongs to the current patient" do
      it "destroys the access and redirects with success notice" do
        delete :destroy, params: { id: access.id }

        expect(response).to redirect_to(patient_professional_accesses_path)
        expect(flash[:notice]).to eq(I18n.t("patient.professional_accesses.messages.revoke_success"))
        expect(PatientProfessionalAccess.exists?(access.id)).to be false
      end
    end

    context "when the access does not belong to the current patient" do
      let(:other_patient_user) { create(:user) }
      let!(:other_patient) { create(:patient, user: other_patient_user, professional: professional) }
      let!(:other_access) do
        create(:patient_professional_access, patient: other_patient, professional: other_pro, granted_by_patient_user: other_patient_user)
      end

      it "does not destroy the access and redirects with alert" do
        delete :destroy, params: { id: other_access.id }

        expect(response).to redirect_to(patient_professional_accesses_path)
        expect(flash[:alert]).to eq(I18n.t("patient.professional_accesses.errors.revoke_not_found"))
        expect(PatientProfessionalAccess.exists?(other_access.id)).to be true
      end
    end
  end
end
