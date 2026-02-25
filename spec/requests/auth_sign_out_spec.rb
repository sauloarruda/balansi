require "rails_helper"

RSpec.describe "Auth sign-out", type: :request do
  let(:user) { create(:user) }
  let!(:patient) { create(:patient, user: user) }

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
    allow_any_instance_of(ApplicationController).to receive(:ensure_patient_personal_profile_completed!)
  end

  describe "layout logout button" do
    it "renders the logout as a form with DELETE method, not a plain GET link" do
      get today_journals_path

      expect(response).to have_http_status(:ok)

      # button_to generates a <form> with hidden _method=delete
      expect(response.body).to include('action="/auth/sign_out"')
      expect(response.body).to include('name="_method" value="delete"')

      # Must NOT be a plain <a href="/auth/sign_out"> (GET link)
      expect(response.body).not_to match(/<a[^>]+href=["']\/auth\/sign_out["']/)
    end
  end

  describe "DELETE /auth/sign_out" do
    before do
      allow(CognitoService).to receive(:logout_url).and_return("https://cognito.example.com/logout")
    end

    it "clears the session" do
      delete auth_sign_out_path
      expect(session[:user_id]).to be_nil
    end

    it "redirects (to Cognito logout URL)" do
      delete auth_sign_out_path
      expect(response).to have_http_status(:see_other)
      expect(response.location).to eq("https://cognito.example.com/logout")
    end

    it "is not accessible via GET" do
      get "/auth/sign_out"
      expect(response).not_to have_http_status(:ok)
    end
  end
end
