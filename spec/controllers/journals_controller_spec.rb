require "rails_helper"

RSpec.describe JournalsController, type: :controller do
  include ActiveSupport::Testing::TimeHelpers
  render_views

  before do
    create(:journal)
    session[:user_id] = User.find(1001).id
  end

  describe "GET #index" do
    it "redirects to today's journal date in the user's timezone" do
      travel_to(Time.utc(2026, 2, 5, 14, 0, 0)) do
        get :index
      end

      expect(response).to redirect_to("/journals/2026-02-05")
    end
  end

  describe "GET #show" do
    it "loads data from fixture-backed journal via factory fallback" do
      journal = create(:journal)

      get :show, params: { date: "2026-02-05" }

      expect(response).to have_http_status(:ok)
      journal_payload = controller.instance_variable_get(:@journal)
      meals_payload = controller.instance_variable_get(:@meals)
      exercises_payload = controller.instance_variable_get(:@exercises)
      expect(journal.id).to eq(3001)
      expect(journal_payload.id).to eq(3001)
      expect(journal_payload.date).to eq(Date.new(2026, 2, 5))
      expect(meals_payload.size).to eq(1)
      expect(exercises_payload.size).to eq(1)
    end

    it "returns empty payload when journal does not exist for date" do
      get :show, params: { date: "2026-02-06" }

      expect(response).to have_http_status(:ok)
      journal_payload = controller.instance_variable_get(:@journal)
      meals_payload = controller.instance_variable_get(:@meals)
      exercises_payload = controller.instance_variable_get(:@exercises)
      expect(journal_payload).to be_a(Journal)
      expect(journal_payload.id).to be_nil
      expect(journal_payload.date).to eq(Date.new(2026, 2, 6))
      expect(meals_payload).to be_empty
      expect(exercises_payload).to be_empty
    end
  end
end
