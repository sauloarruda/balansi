require "rails_helper"

RSpec.describe Patients::PersonalProfilesController, type: :controller do
  include ActiveSupport::Testing::TimeHelpers
  render_views

  let(:user) { create(:user) }
  let!(:patient) { create(:patient, :incomplete_profile, user: user) }

  before do
    session[:user_id] = user.id
  end

  describe "GET #show" do
    it "renders completion form when profile is incomplete" do
      patient.update!(
        gender: nil,
        birth_date: nil,
        weight_kg: nil,
        height_cm: nil,
        phone_e164: nil,
        profile_completed_at: nil
      )

      get :show

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("patient_personal_profile.show.title"))
    end

    it "renders profile page when profile is already complete" do
      patient.update!(
        gender: "female",
        birth_date: Date.new(1990, 1, 1),
        weight_kg: 70.0,
        height_cm: 170.0,
        phone_e164: "+5511999999999",
        profile_completed_at: Time.zone.local(2026, 2, 5, 10, 0, 0),
        profile_last_updated_at: Time.zone.local(2026, 2, 5, 10, 0, 0)
      )

      get :show

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(patient.user.name)
    end
  end

  describe "PATCH #update" do
    it "completes profile and redirects to root" do
      travel_to(Time.zone.local(2026, 2, 7, 9, 30, 0)) do
        patch :update, params: {
          patient: {
            gender: "male",
            birth_date: "10/03/1991",
            weight_kg: "78.5",
            height_cm: "182.0",
            phone_country: "BR",
            phone_national_number: "(11) 98888-7777"
          }
        }
      end

      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq(I18n.t("patient_personal_profile.messages.completed_success"))

      patient.reload
      expect(patient.gender).to eq("male")
      expect(patient.birth_date).to eq(Date.new(1991, 3, 10))
      expect(patient.weight_kg).to eq(78.5)
      expect(patient.height_cm).to eq(182.0)
      expect(patient.phone_e164).to eq("+5511988887777")
      expect(patient.profile_completed_at).to be_present
      expect(patient.profile_last_updated_at).to be_present
    end

    it "parses birth_date using en locale format when user language is en" do
      user.update!(language: "en")

      patch :update, params: {
        patient: {
          gender: "male",
          birth_date: "03/10/1991",
          weight_kg: "78.5",
          height_cm: "182.0",
          phone_country: "US",
          phone_national_number: "(415) 555-2671"
        }
      }

      expect(response).to redirect_to(root_path)
      expect(patient.reload.birth_date).to eq(Date.new(1991, 3, 10))
      expect(patient.phone_e164).to eq("+14155552671")
    end

    it "renders unprocessable_entity when birth_date format is invalid for locale" do
      patch :update, params: {
        patient: {
          gender: "male",
          birth_date: "31/31/1991",
          weight_kg: "78.5",
          height_cm: "182.0",
          phone_country: "BR",
          phone_national_number: "(11) 98888-7777"
        }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("patient_personal_profile.messages.birth_date_invalid"))

      patient.reload
      expect(patient.birth_date).to be_nil
      expect(patient.profile_completed_at).to be_nil
    end

    it "renders unprocessable_entity when required fields are invalid" do
      patch :update, params: {
        patient: {
          gender: "invalid",
          birth_date: "",
          weight_kg: "10",
          height_cm: "90",
          phone_country: "BR",
          phone_national_number: "12345"
        }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("patient_personal_profile.show.title"))

      patient.reload
      expect(patient.profile_completed_at).to be_nil
      expect(patient.profile_last_updated_at).to be_nil
    end

    it "renders unprocessable_entity when phone does not match selected country" do
      patch :update, params: {
        patient: {
          gender: "male",
          birth_date: "10/03/1991",
          weight_kg: "78.5",
          height_cm: "182.0",
          phone_country: "US",
          phone_national_number: "(11) 98888-7777"
        }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("patient_personal_profile.messages.phone_invalid"))

      patient.reload
      expect(patient.phone_e164).to be_nil
      expect(patient.profile_completed_at).to be_nil
    end
  end
end
