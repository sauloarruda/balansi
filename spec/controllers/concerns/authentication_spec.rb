require "rails_helper"

RSpec.describe Authentication, type: :controller do
  include_context "controller concern test",
    skip_auth: :partial,
    skip_auth_actions: [ :public_action ],
    actions: [ :public_action, :protected_action ],
    routes: [
      { path: "public_action", action: "public_action" },
      { path: "protected_action", action: "protected_action" }
    ],
    skip_default_route: true

  let(:user) { create(:user) }

  describe "#current_user" do
    it "returns nil when no user in session" do
      get :public_action
      expect(controller.send(:current_user)).to be_nil
    end

    it "returns user when user_id in session" do
      session[:user_id] = user.id
      get :public_action
      expect(controller.send(:current_user).id).to eq(user.id)
    end

    it "clears session when user not found" do
      session[:user_id] = 99999
      get :public_action
      expect(controller.send(:current_user)).to be_nil
      expect(session[:user_id]).to be_nil
      expect(session[:refresh_token]).to be_nil
    end

    it "is memoized" do
      session[:user_id] = user.id
      get :public_action
      first_call = controller.send(:current_user)
      second_call = controller.send(:current_user)
      expect(first_call).to be(second_call)
    end
  end

  describe "#authenticate_user!" do
    it "redirects to sign_in when no user" do
      get :protected_action
      expect(response).to redirect_to("/auth/sign_in")
    end

    it "allows access when user is authenticated" do
      session[:user_id] = user.id
      create(:patient, user: user)
      get :protected_action
      expect(response).to have_http_status(:success)
    end
  end

  describe "development test user login (?test_user_id=)" do
    before do
      allow(Rails.env).to receive(:development?).and_return(true)
    end

    it "does not run when test_user_id is blank" do
      get :protected_action
      expect(response).to redirect_to("/auth/sign_in")
    end

    it "redirects to sign_in with alert when user not found" do
      get :protected_action, params: { test_user_id: 99999 }
      expect(response).to redirect_to("/auth/sign_in")
      expect(flash[:alert]).to include("99999")
    end

    it "sets session and redirects to same path without param when user exists" do
      create(:patient, user: user)
      get :protected_action, params: { test_user_id: user.id }
      expect(response).to redirect_to("/protected_action")
      expect(session[:user_id]).to eq(user.id)
    end
  end
end
