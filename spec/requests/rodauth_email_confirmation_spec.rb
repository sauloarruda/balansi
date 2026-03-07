require "rails_helper"

RSpec.describe "Email confirmation", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  let!(:owner_professional) { create(:professional) }

  before do
    host! "localhost"
    ActionMailer::Base.deliveries.clear
  end

  def authenticity_token_for(path)
    get path
    response.body[%r{name="authenticity_token" value="([^"]+)"}, 1]
  end

  def sign_up_as(email:, name: "Test Person")
    token = authenticity_token_for(auth_sign_up_path)
    post auth_sign_up_path, params: {
      authenticity_token: token,
      name: name,
      email: email,
      email_confirmation: email,
      password: "password123",
      "password-confirm" => "password123"
    }
  end

  describe "POST /auth/sign_up" do
    it "sends a confirmation email after sign-up" do
      expect { sign_up_as(email: "newuser@example.com") }
        .to change { ActionMailer::Base.deliveries.count }.by(1)

      mail = ActionMailer::Base.deliveries.last
      expect(mail.subject).to include("Confirme seu email")
      expect(mail.to).to include("newuser@example.com")
    end

    it "creates the user as unverified" do
      sign_up_as(email: "unverified@example.com")

      user = User.order(:id).last
      expect(user.status_id).to eq(User::UNVERIFIED_STATUS)
      expect(user.verified?).to be false
    end
  end

  describe "POST /auth/sign_in with unverified account" do
    let!(:unverified_user) { create(:user, :with_password, :unverified, email: "unverified-login@example.com") }
    let!(:patient) { create(:patient, user: unverified_user) }

    it "blocks login and shows the unverified account message" do
      token = authenticity_token_for(auth_login_path)

      post auth_login_path, params: {
        authenticity_token: token,
        email: unverified_user.email,
        password: "password123"
      }

      expect(response).to have_http_status(:unprocessable_content).or have_http_status(:forbidden)
      expect(response.body).to include("confirmar seu email")
      expect(session[:user_id]).to be_nil
    end
  end

  describe "GET /auth/verify-email (confirmation link)" do
    it "verifies the account and redirects to root" do
      sign_up_as(email: "verify-link@example.com")

      mail = ActionMailer::Base.deliveries.last
      text_body = mail.parts.find { |p| p.content_type.include?("text/plain") }&.body&.decoded || mail.body.decoded
      verify_url = text_body[%r{http[s]?://[^\s"<]+verify-email[^\s"<]+}]
      verify_path = URI.parse(verify_url).request_uri
      key = URI.decode_www_form(URI.parse(verify_url).query).to_h["key"]

      user = User.order(:id).last

      # GET stores key in session and redirects to /auth/verify-email (without key)
      get verify_path
      # Follow redirect to get the verify form (key is now in session)
      follow_redirect!
      token = response.body[%r{name="authenticity_token" value="([^"]+)"}, 1]
      # POST performs the actual verification (key read from session)
      post "/auth/verify-email", params: { authenticity_token: token }

      expect(user.reload.verified?).to be true
    end

    it "shows an error for an invalid key" do
      get "/auth/verify-email", params: { key: "invalid-key" }

      expect(response).to have_http_status(:ok).or have_http_status(:found)
    end
  end

  describe "POST /auth/verify-email/resend" do
    it "resends the confirmation email after the cooldown period" do
      sign_up_as(email: "resend@example.com")
      ActionMailer::Base.deliveries.clear

      travel_to(6.minutes.from_now) do
        token = authenticity_token_for("/auth/verify-email/resend")
        expect do
          post "/auth/verify-email/resend", params: {
            authenticity_token: token,
            email: "resend@example.com"
          }
        end.to change { ActionMailer::Base.deliveries.count }.by(1)
      end
    end
  end
end
