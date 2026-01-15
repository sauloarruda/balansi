# spec/controllers/auth/sessions_controller_spec.rb
#
# Tests for Auth::SessionsController which handles OAuth authentication initiation
# and session destruction.
#
# Key test areas:
# - CSRF token generation and storage
# - Redirect to Cognito login/signup URLs
# - State parameter building with optional business params
# - Browser language detection
# - Session clearing on logout
# - Error handling for missing credentials
#
# Note: Uses controller specs which test the controller in isolation.

require "rails_helper"

RSpec.describe Auth::SessionsController, type: :controller do
  include CognitoCredentialsHelper
  include AuthControllerTestHelpers

  let(:test_credentials_hash) do
    {
      cognito: {
        user_pool_id: "sa-east-1_test_pool",
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        domain: "test-domain",
        region: "sa-east-1",
        redirect_uri: "http://localhost:3000/auth/callbacks",
        logout_uri: "http://localhost:3000/"
      }
    }
  end

  # Setup routes
  before do
    routes.draw do
      get "/auth/sign_up", to: "auth/sessions#new"
      get "/auth/sign_in", to: "auth/sessions#new", as: :auth_login_path
      delete "/auth/sign_out", to: "auth/sessions#destroy"
      root to: "home#index"
    end
  end

  before do
    mock_credentials
  end

  after do
    restore_credentials
  end

  describe "GET #new" do
    let(:csrf_token) { SecureRandom.urlsafe_base64(AuthControllerTestHelpers::CSRF_TOKEN_LENGTH) }

    before do
      allow(SecureRandom).to receive(:urlsafe_base64).with(AuthControllerTestHelpers::CSRF_TOKEN_LENGTH).and_return(csrf_token)
      allow(CognitoService).to receive(:login_url).and_call_original
      allow(CognitoService).to receive(:signup_url).and_call_original
    end

    shared_examples "generates and stores CSRF token" do
      it "generates CSRF token and stores in session" do
        get :new
        expect(session[:oauth_state]).to eq(csrf_token)
      end

      it "builds state parameter with CSRF token" do
        get :new
        encoded_token = CGI.escape(csrf_token)
        expect(response.location).to include("csrf_token%3D#{encoded_token}")
      end
    end

    shared_examples "redirects to Cognito" do |path_type|
      it "redirects to Cognito #{path_type} URL" do
        get :new
        expect(response).to have_http_status(:found)
        expect(response.location).to include("/oauth2/authorize")
        expect(response.location).to include("client_id=test_client_id")
      end

      it "allows redirect to other hosts" do
        get :new
        expect(response).to have_http_status(:found)
      end
    end

    context "when accessing sign_in path" do
      before do
        request.path = "/auth/sign_in"
      end

      include_examples "generates and stores CSRF token"
      include_examples "redirects to Cognito", "login"

      it "detects browser language and passes to CognitoService" do
        request.headers["Accept-Language"] = "en-US"
        get :new
        expect(response).to have_http_status(:found)
        expect(response.location).to include("/oauth2/authorize")
      end

      it "defaults to :pt locale when Accept-Language header is missing" do
        request.headers["Accept-Language"] = nil
        get :new
        expect(response).to have_http_status(:found)
        expect(response.location).to include("/oauth2/authorize")
      end
    end

    context "when accessing sign_up path" do
      before do
        request.path = "/auth/sign_up"
      end

      include_examples "generates and stores CSRF token"
      include_examples "redirects to Cognito", "signup"

      it "detects browser language and passes to CognitoService" do
        request.headers["Accept-Language"] = "pt-BR"
        get :new
        expect(response).to have_http_status(:found)
        expect(response.location).to include("/oauth2/authorize")
      end
    end

    context "with professional_id parameter" do
      let(:professional_id) { "12345" }

      shared_examples "includes professional_id in state" do |path|
        it "includes professional_id in state parameter for #{path}" do
          request.path = "/auth/#{path}"
          get :new, params: { professional_id: professional_id }
          encoded_id = CGI.escape(professional_id)
          expect(response.location).to include("professional_id%3D#{encoded_id}")
        end
      end

      include_examples "includes professional_id in state", "sign_in"
      include_examples "includes professional_id in state", "sign_up"

      it "does not include professional_id when parameter is blank" do
        request.path = "/auth/sign_in"
        get :new, params: { professional_id: "" }
        expect(response.location).not_to include("professional_id=")
      end

      it "does not include professional_id when parameter is nil" do
        request.path = "/auth/sign_in"
        get :new, params: { professional_id: nil }
        expect(response.location).not_to include("professional_id=")
      end
    end

    context "when CognitoService raises MissingCredentialsError" do
      before do
        mock_credentials({})
        request.path = "/auth/sign_in"
      end

      it "renders new template with service_unavailable status" do
        get :new
        expect(response).to have_http_status(:service_unavailable)
      end

      it "stores oauth_state in session before error occurs" do
        get :new
        expect(session[:oauth_state]).to eq(csrf_token)
      end
    end

    context "CSRF token generation" do
      before do
        request.path = "/auth/sign_in"
      end

      it "generates unique tokens for each request" do
        allow(SecureRandom).to receive(:urlsafe_base64).with(AuthControllerTestHelpers::CSRF_TOKEN_LENGTH).and_call_original

        get :new
        first_session_state = session[:oauth_state]

        session.clear
        get :new
        second_session_state = session[:oauth_state]

        expect(first_session_state).to be_present
        expect(second_session_state).to be_present
        expect(first_session_state).not_to eq(second_session_state)
      end

      it "generates tokens with correct length" do
        get :new
        token = session[:oauth_state]
        decoded = Base64.urlsafe_decode64(token)
        expect(decoded.length).to eq(AuthControllerTestHelpers::CSRF_TOKEN_LENGTH)
      end

      it "generates URL-safe base64 tokens" do
        get :new
        token = session[:oauth_state]
        expect(token).not_to include("+")
        expect(token).not_to include("/")
      end

      context "when token generation raises exception" do
        it "handles SecureRandom errors gracefully" do
          allow(SecureRandom).to receive(:urlsafe_base64).and_raise(StandardError.new("Random error"))

          expect { get :new }.to raise_error(StandardError)
        end
      end
    end
  end

  describe "DELETE #destroy" do
    before do
      allow(CognitoService).to receive(:logout_url).and_call_original
      session[:user_id] = 123
      session[:oauth_state] = "some_state"
    end

    it "clears user_id from session" do
      delete :destroy
      expect(session[:user_id]).to be_nil
    end

    it "clears oauth_state from session" do
      delete :destroy
      expect(session[:oauth_state]).to be_nil
    end

    it "redirects to Cognito logout URL" do
      delete :destroy
      expect(response).to have_http_status(:see_other)
      expect(response.location).to include("/logout")
      expect(response.location).to include("client_id=test_client_id")
    end

    it "uses :see_other status for redirect" do
      delete :destroy
      expect(response).to have_http_status(:see_other)
    end

    it "allows redirect to other hosts" do
      delete :destroy
      expect(response).to have_http_status(:see_other)
    end

    it "calls CognitoService.logout_url" do
      delete :destroy
      expect(CognitoService).to have_received(:logout_url)
    end

    context "when CognitoService raises MissingCredentialsError" do
      before do
        allow(CognitoService).to receive(:logout_url).and_raise(
          CognitoService::MissingCredentialsError.new("Cognito credentials not configured")
        )
      end

      it "redirects to root_path" do
        delete :destroy
        expect(response).to redirect_to(root_path)
      end

      it "uses :see_other status for redirect" do
        delete :destroy
        expect(response).to have_http_status(:see_other)
      end

      it "still clears Rails session" do
        delete :destroy
        expect(session[:user_id]).to be_nil
        expect(session[:oauth_state]).to be_nil
      end
    end

    context "session handling" do
      it "clears all session data" do
        session[:user_id] = 123
        session[:oauth_state] = "state"
        session[:refresh_token] = "token"
        session[:custom_data] = "value"

        delete :destroy

        expect(session.to_hash).to be_empty
      end

      it "handles session storage failures gracefully" do
        allow(session).to receive(:clear).and_raise(StandardError.new("Session error"))

        expect { delete :destroy }.to raise_error(StandardError)
      end
    end
  end

  describe "private methods" do
    describe "#generate_state_token" do
      it "generates a secure random token" do
        token = controller.send(:generate_state_token)
        expect(token).to be_a(String)
        expect(token.length).to be > 0
      end

      it "uses SecureRandom.urlsafe_base64 with correct length" do
        expect(SecureRandom).to receive(:urlsafe_base64).with(AuthControllerTestHelpers::CSRF_TOKEN_LENGTH).and_return("test_token")
        token = controller.send(:generate_state_token)
        expect(token).to eq("test_token")
      end

      it "generates URL-safe base64 tokens" do
        token = controller.send(:generate_state_token)
        expect(token).not_to include("+")
        expect(token).not_to include("/")
      end
    end
  end
end
