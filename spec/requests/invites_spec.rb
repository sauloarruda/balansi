require "rails_helper"

RSpec.describe "Invites", type: :request do
  describe "GET /:invite_code" do
    it "redirects to signup with the invite_code when the code is valid" do
      professional = create(:professional)

      get "/#{professional.invite_code}"

      expect(response).to redirect_to("/auth/sign_up?invite_code=#{professional.invite_code}")
    end

    it "redirects to sign_in when the invite_code is unknown" do
      get "/XXXXXX"

      expect(response).to redirect_to("/auth/sign_in")
    end

    it "is case-insensitive — upcases the code before lookup" do
      professional = create(:professional)
      lower_code = professional.invite_code.downcase

      get "/#{lower_code}"

      expect(response).to redirect_to("/auth/sign_up?invite_code=#{professional.invite_code}")
    end
  end
end
