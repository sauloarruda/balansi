require "rails_helper"

RSpec.describe "Auth sign-out", type: :request do
  let(:user) { create(:user) }
  let!(:patient) { create(:patient, user: user) }

  before do
    host! "localhost"
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
    allow_any_instance_of(ApplicationController).to receive(:ensure_patient_personal_profile_completed!)
  end

  describe "layout logout button" do
    it "renders the logout as a POST form, not a plain GET link" do
      get today_journals_path

      expect(response).to have_http_status(:ok)

      expect(response.body).to include('action="/auth/sign_out"')
      expect(response.body).not_to include('name="_method" value="delete"')

      expect(response.body).not_to match(/<a[^>]+href=["']\/auth\/sign_out["']/)
    end
  end

  describe "POST /auth/sign_out" do
    it "clears the session" do
      post auth_sign_out_path
      expect(session[:user_id]).to be_nil
    end

    it "redirects back to the sign-in page" do
      post auth_sign_out_path
      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(auth_login_path)
    end

    it "shows a confirmation form on GET without logging the user out" do
      get "/auth/sign_out"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="logout-form"')
    end
  end
end
