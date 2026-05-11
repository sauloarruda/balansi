require "rails_helper"

RSpec.describe Patients::RecipesController, type: :controller do
  render_views

  let(:patient_user) { create(:user) }
  let!(:patient) { create(:patient, user: patient_user) }

  before { session[:user_id] = patient_user.id }

  describe "GET #index" do
    it "lists recipes owned by the current patient" do
      recipe = create(:recipe, patient: patient, name: "Patient soup")
      other_recipe = create(:recipe, name: "Other patient soup")

      get :index

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(recipe.name)
      expect(response.body).to include(I18n.t("patient.recipes.nutrition.calories_per_portion"))
      expect(response.body).to include("400 kcal")
      expect(response.body).to include("30,25 g")
      expect(response.body).not_to include(other_recipe.name)
    end

    it "renders the empty state" do
      get :index

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("patient.recipes.index.empty_title"))
      expect(response.body).to include(I18n.t("patient.recipes.index.empty"))
      expect(response.body).to include(I18n.t("patient.recipes.actions.create_first"))
    end
  end

  describe "GET #show" do
    it "shows a recipe owned by the current patient" do
      recipe = create(:recipe, patient: patient, name: "Breakfast cake", proteins: 12.25, carbs: 30.5, fats: 8.75)

      get :show, params: { id: recipe.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(recipe.name)
      expect(response.body).to include(recipe.ingredients)
      expect(response.body).to include("12,25")
      expect(response.body).to include("30,5")
      expect(response.body).to include("8,75")
      expect(response.body).to include(I18n.t("patient.recipes.show.per_portion"))
      expect(response.body).to include("6,13 g")
    end

    it "does not show recipes owned by another patient" do
      other_recipe = create(:recipe, name: "Private recipe")

      get :show, params: { id: other_recipe.id }

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(other_recipe.name)
    end
  end

  describe "GET #new" do
    it "renders the new recipe form" do
      get :new

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("recipe[name]")
      expect(response.body).to include(I18n.t("patient.recipes.actions.create"))
    end
  end

  describe "POST #create" do
    let(:valid_params) do
      {
        name: "Lentil stew",
        ingredients: "Lentils, carrots, onion",
        instructions: "Cook until tender.",
        yield_portions: 4,
        calories: 900,
        proteins: 48.25,
        carbs: 120.5,
        fats: 18.75
      }
    end

    it "creates a recipe for the current patient" do
      expect do
        post :create, params: { recipe: valid_params }
      end.to change { patient.recipes.count }.by(1)

      recipe = patient.recipes.last
      expect(recipe.name).to eq("Lentil stew")
      expect(recipe.proteins).to eq(48.25)
      expect(recipe.carbs).to eq(120.5)
      expect(recipe.fats).to eq(18.75)
      expect(response).to redirect_to(patient_recipe_path(recipe))
      expect(flash[:notice]).to eq(I18n.t("patient.recipes.messages.created"))
    end

    it "re-renders the form when validation fails" do
      expect do
        post :create, params: { recipe: valid_params.merge(name: "") }
      end.not_to change(Recipe, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("forms.errors.alert"))
    end
  end

  describe "GET #edit" do
    it "renders the edit form for a recipe owned by the current patient" do
      recipe = create(:recipe, patient: patient)

      get :edit, params: { id: recipe.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("recipe[name]")
      expect(response.body).to include(I18n.t("patient.recipes.actions.update"))
    end

    it "does not render the edit form for another patient's recipe" do
      other_recipe = create(:recipe)

      get :edit, params: { id: other_recipe.id }

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(other_recipe.name)
    end
  end

  describe "PATCH #update" do
    let!(:recipe) { create(:recipe, patient: patient, name: "Original name") }

    it "updates a recipe owned by the current patient" do
      patch :update, params: {
        id: recipe.id,
        recipe: {
          name: "Updated name",
          ingredients: recipe.ingredients,
          yield_portions: 3
        }
      }

      expect(response).to redirect_to(patient_recipe_path(recipe))
      expect(flash[:notice]).to eq(I18n.t("patient.recipes.messages.updated"))
      expect(recipe.reload.name).to eq("Updated name")
      expect(recipe.yield_portions).to eq(3)
    end

    it "re-renders the edit form when validation fails" do
      patch :update, params: {
        id: recipe.id,
        recipe: {
          name: "",
          ingredients: recipe.ingredients,
          yield_portions: 3
        }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("forms.errors.alert"))
      expect(recipe.reload.name).to eq("Original name")
    end

    it "does not update recipes owned by another patient" do
      other_recipe = create(:recipe, name: "Other recipe")

      patch :update, params: {
        id: other_recipe.id,
        recipe: {
          name: "Leaked update",
          ingredients: other_recipe.ingredients,
          yield_portions: 2
        }
      }

      expect(response).to have_http_status(:not_found)
      expect(other_recipe.reload.name).to eq("Other recipe")
    end
  end

  describe "DELETE #destroy" do
    it "deletes a recipe owned by the current patient" do
      recipe = create(:recipe, patient: patient)

      expect do
        delete :destroy, params: { id: recipe.id }
      end.to change { patient.recipes.count }.by(-1)

      expect(response).to redirect_to(patient_recipes_path)
      expect(response).to have_http_status(:see_other)
      expect(flash[:notice]).to eq(I18n.t("patient.recipes.messages.deleted"))
    end

    it "does not delete recipes owned by another patient" do
      other_recipe = create(:recipe)

      expect do
        delete :destroy, params: { id: other_recipe.id }
      end.not_to change(Recipe, :count)

      expect(response).to have_http_status(:not_found)
      expect(Recipe.exists?(other_recipe.id)).to be true
    end
  end
end
