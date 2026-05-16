require "rails_helper"

RSpec.describe Patients::Recipes::SearchController, type: :controller do
  let(:patient_user) { create(:user) }
  let!(:patient) { create(:patient, user: patient_user) }

  before { session[:user_id] = patient_user.id }

  describe "GET #index" do
    it "returns one current patient recipe by id" do
      recipe = create(:recipe, patient: patient, name: "Created recipe", calories: 450)
      create(:recipe, patient: patient, name: "Other recipe")

      get :index, params: { recipe_id: recipe.id }, format: :json

      payload = JSON.parse(response.body)
      expect(response).to have_http_status(:ok)
      expect(payload.size).to eq(1)
      expect(payload.first).to include(
        "id" => recipe.id,
        "name" => "Created recipe",
        "calories_per_portion" => 450
      )
    end

    it "does not return another patient's recipe by id" do
      other_recipe = create(:recipe, name: "Private recipe")

      get :index, params: { recipe_id: other_recipe.id }, format: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to be_empty
    end
  end
end
