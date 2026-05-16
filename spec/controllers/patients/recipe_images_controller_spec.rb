require "rails_helper"

RSpec.describe Patients::RecipeImagesController, type: :controller do
  let(:patient_user) { create(:user) }
  let!(:patient) { create(:patient, user: patient_user) }

  before { session[:user_id] = patient_user.id }

  describe "DELETE #destroy" do
    it "deletes an image from a recipe owned by the current patient" do
      recipe = create(:recipe, patient: patient)
      image = create(:image, recipe: recipe)

      expect do
        delete :destroy, params: { recipe_id: recipe.id, id: image.id }
      end.to change { recipe.images.count }.by(-1)

      expect(response).to redirect_to(edit_patient_recipe_path(recipe))
      expect(response).to have_http_status(:see_other)
      expect(flash[:notice]).to eq(I18n.t("patient.recipes.messages.image_deleted"))
    end

    it "does not delete images from recipes owned by another patient" do
      other_recipe = create(:recipe)
      image = create(:image, recipe: other_recipe)

      expect do
        delete :destroy, params: { recipe_id: other_recipe.id, id: image.id }
      end.not_to change(Image, :count)

      expect(response).to have_http_status(:not_found)
      expect(Image.exists?(image.id)).to be true
    end

    it "does not delete images from discarded recipes" do
      recipe = create(:recipe, patient: patient)
      image = create(:image, recipe: recipe)
      recipe.discard!

      expect do
        delete :destroy, params: { recipe_id: recipe.id, id: image.id }
      end.not_to change(Image, :count)

      expect(response).to have_http_status(:not_found)
      expect(Image.exists?(image.id)).to be true
    end
  end
end
