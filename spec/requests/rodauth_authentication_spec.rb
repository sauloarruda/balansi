require "rails_helper"

RSpec.describe "Rodauth authentication", type: :request do
  let!(:owner_professional) { create(:professional) }

  before do
    host! "localhost"
  end

  def authenticity_token_for(path)
    get path
    response.body[%r{name="authenticity_token" value="([^"]+)"}, 1]
  end

  describe "GET /auth/sign_in" do
    it "renders the local sign-in page" do
      get auth_login_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Entrar")
      expect(response.body).to include('name="email"')
    end

    it "renders the page in the browser language for unauthenticated requests" do
      get auth_login_path, headers: {
        "Accept-Language" => "en-US,en;q=0.9"
      }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sign in")
      expect(response.body).to include("Access your account to continue your care.")
      expect(response.body).not_to include("Acesse sua conta para continuar seu acompanhamento.")
    end
  end

  describe "POST /auth/sign_up" do
    it "creates a user and patient profile, then redirects to verify-email page" do
      token = authenticity_token_for(auth_sign_up_path(invite_code: owner_professional.invite_code))

      expect do
        post auth_sign_up_path, params: {
          authenticity_token: token,
          name: "Nova Pessoa",
          email: "nova@example.com",
          password: "password123",
          "password-confirm" => "password123",
          invite_code: owner_professional.invite_code
        }, headers: {
          "Accept-Language" => "en-US"
        }
      end.to change(User, :count).by(1).and change(Patient, :count).by(1)

      user = User.order(:id).last

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to("/auth/verify-email/resend")
      expect(session[:user_id]).to be_nil
      expect(user.password_hash).to be_present
      expect(user.language).to eq("en")
      expect(user.timezone).to eq("America/Sao_Paulo")
      expect(user.patient.professional_id).to eq(owner_professional.id)
      expect(user.status_id).to eq(User::UNVERIFIED_STATUS)
    end

    it "links the patient to the professional identified by invite_code" do
      selected_professional = create(:professional)
      token = authenticity_token_for(auth_sign_up_path(invite_code: selected_professional.invite_code))

      post auth_sign_up_path, params: {
        authenticity_token: token,
        name: "Paciente Vinculado",
        email: "vinculado@example.com",
        password: "password123",
        "password-confirm" => "password123",
        invite_code: selected_professional.invite_code
      }

      expect(response).to have_http_status(:found)
      expect(User.order(:id).last.patient.professional_id).to eq(selected_professional.id)
    end

    it "shows a specific message when the email is already taken" do
      existing_user = create(:user, email: "existing-signup@example.com")
      create(:patient, user: existing_user)
      token = authenticity_token_for(auth_sign_up_path(invite_code: owner_professional.invite_code))

      post auth_sign_up_path, params: {
        authenticity_token: token,
        name: "Pessoa Duplicada",
        email: existing_user.email,
        password: "password123",
        "password-confirm" => "password123",
        invite_code: owner_professional.invite_code
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Já existe uma conta com este email.")
      expect(response.body).not_to include("Informe um email válido.")
    end

    it "shows validation errors in the browser language for unauthenticated requests" do
      existing_user = create(:user, email: "existing-english-signup@example.com")
      create(:patient, user: existing_user)
      token = authenticity_token_for(auth_sign_up_path(invite_code: owner_professional.invite_code))

      post auth_sign_up_path, params: {
        authenticity_token: token,
        name: "Existing Person",
        email: existing_user.email,
        password: "password123",
        "password-confirm" => "password123",
        invite_code: owner_professional.invite_code
      }, headers: {
        "Accept-Language" => "en-US,en;q=0.9"
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("An account with this email already exists.")
      expect(response.body).not_to include("Já existe uma conta com este email.")
    end

    it "redirects to sign_in when no invite_code is provided on GET" do
      get auth_sign_up_path
      expect(response).to redirect_to(auth_login_path)
    end

    it "returns 422 with error when posting without an invite_code" do
      token = authenticity_token_for(auth_sign_up_path(invite_code: owner_professional.invite_code))

      post auth_sign_up_path, params: {
        authenticity_token: token,
        name: "Sem Codigo",
        email: "semcodigo@example.com",
        password: "password123",
        "password-confirm" => "password123"
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to match(/Invalid or expired invite code\.?/)
        .or match(/Código de convite inválido(?: ou expirado)?\.?/)
    end
  end

  describe "POST /auth/sign_in" do
    let!(:user) { create(:user, :with_password, email: "login@example.com") }
    let!(:patient) { create(:patient, user: user) }

    it "authenticates an existing account" do
      token = authenticity_token_for(auth_login_path)

      post auth_login_path, params: {
        authenticity_token: token,
        email: user.email,
        password: "password123"
      }

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(root_path)
      expect(session[:user_id]).to eq(user.id)
    end
  end

  describe "POST /auth/sign_out" do
    let!(:user) { create(:user, :with_password, email: "logout@example.com") }
    let!(:patient) { create(:patient, user: user) }

    before do
      login_token = authenticity_token_for(auth_login_path)

      post auth_login_path, params: {
        authenticity_token: login_token,
        email: user.email,
        password: "password123"
      }
    end

    it "logs out the current user" do
      logout_token = authenticity_token_for(auth_sign_out_path)

      post auth_sign_out_path, params: { authenticity_token: logout_token }

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(auth_login_path)
      expect(session[:user_id]).to be_nil
    end
  end

  describe "legacy sessions without authenticated_by" do
    let!(:user) { create(:user, :with_password, email: "legacy-session@example.com") }
    let!(:patient) { create(:patient, user: user) }

    it "does not crash when a pre-Rodauth session hits auth routes" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))

      get today_journals_path, params: { test_user_id: user.id }

      expect(response).to redirect_to(today_journals_path)

      expect { get auth_login_path }.not_to raise_error
      expect(response).to have_http_status(:found).or have_http_status(:ok)
    end
  end
end
