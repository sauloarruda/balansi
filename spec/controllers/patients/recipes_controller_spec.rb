require "rails_helper"
require "base64"
require "tempfile"

RSpec.describe Patients::RecipesController, type: :controller do
  render_views

  PNG_IMAGE = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
  ).freeze

  let(:patient_user) { create(:user) }
  let!(:patient) { create(:patient, user: patient_user) }

  before { session[:user_id] = patient_user.id }

  def uploaded_recipe_image
    file = Tempfile.new([ "recipe", ".png" ])
    file.binmode
    file.write(PNG_IMAGE)
    file.rewind
    (@uploaded_recipe_image_files ||= []) << file

    Rack::Test::UploadedFile.new(file.path, "image/png", true, original_filename: "recipe.png")
  end

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

    it "renders recipe images with high-resolution modals" do
      recipe = create(:recipe, patient: patient, name: "Recipe with image")
      image = create(:image, recipe: recipe)
      mark_variant_processed(image, :standard)
      mark_variant_processed(image, :large)

      get :index

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("rails/active_storage/representations")
      expect(response.body).to include(%(data-modal-target=))
      expect(response.body).to include(%(data-modal-toggle=))
      expect(response.body).to include(%(data-modal-hide=))
      expect(response.body).to include(I18n.t("patient.recipes.actions.view_image"))
      expect(response.body).to include(%(alt="#{recipe.name}"))
    end

    it "renders a processing placeholder before image variants are ready" do
      recipe = create(:recipe, patient: patient, name: "Recipe with pending image")
      create(:image, recipe: recipe)

      get :index

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("image-processing")
      expect(response.body).to include(I18n.t("patient.recipes.images.processing"))
    end

    it "renders multiple recipe images as a carousel" do
      recipe = create(:recipe, patient: patient, name: "Recipe with images")
      create(:image, recipe: recipe, position: 0)
      create(:image, recipe: recipe, position: 1)

      get :index

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(data-carousel="static"))
      expect(response.body).to include(%(data-carousel-prev))
      expect(response.body).to include(%(data-carousel-next))
      expect(response.body).to include(%(data-modal-target=))
      expect(response.body).to include(%(data-modal-toggle=))
      expect(response.body).to include(I18n.t("patient.recipes.actions.view_image"))
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
      expect(response.body).to include(I18n.t("patient.recipes.show.nutrition_per_portion"))
      expect(response.body).to include("200 g")
    end

    it "shows the standard recipe image with a high-resolution modal" do
      recipe = create(:recipe, patient: patient, name: "Recipe with image")
      image = create(:image, recipe: recipe)
      mark_variant_processed(image, :standard)
      mark_variant_processed(image, :large)

      get :show, params: { id: recipe.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("rails/active_storage/representations")
      expect(response.body).to include(%(data-modal-target=))
      expect(response.body).to include(%(data-modal-toggle=))
      expect(response.body).to include(%(data-modal-hide=))
      expect(response.body).to include(I18n.t("patient.recipes.actions.view_image"))
      expect(response.body).to include(%(alt="#{recipe.name}"))
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
        portion_size_grams: 200,
        calories: 450,
        proteins: 24.12,
        carbs: 60.25,
        fats: 9.38
      }
    end

    it "creates a recipe for the current patient" do
      expect do
        post :create, params: { recipe: valid_params }
      end.to change { patient.recipes.count }.by(1)

      recipe = patient.recipes.last
      expect(recipe.name).to eq("Lentil stew")
      expect(recipe.portion_size_grams).to eq(200)
      expect(recipe.proteins).to eq(24.12)
      expect(recipe.carbs).to eq(60.25)
      expect(recipe.fats).to eq(9.38)
      expect(response).to redirect_to(patient_recipe_path(recipe))
      expect(flash[:notice]).to eq(I18n.t("patient.recipes.messages.created"))
    end

    it "uploads images for the recipe" do
      expect do
        post :create, params: { recipe: valid_params.merge(images: [ uploaded_recipe_image, uploaded_recipe_image ]) }
      end.to change { patient.recipes.count }.by(1)

      recipe = patient.recipes.last
      expect(recipe.images.count).to eq(2)
      expect(recipe.images.first.file).to be_attached
      expect(recipe.images.first.file.blob.content_type).to eq("image/png")
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
      image = create(:image, recipe: recipe)

      get :edit, params: { id: recipe.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("recipe[name]")
      expect(response.body).to include(I18n.t("patient.recipes.actions.update"))
      expect(response.body).to include(patient_recipe_image_path(recipe, image))
      expect(response.body).to include(I18n.t("patient.recipes.actions.delete_image"))
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
          portion_size_grams: 150
        }
      }

      expect(response).to redirect_to(patient_recipe_path(recipe))
      expect(flash[:notice]).to eq(I18n.t("patient.recipes.messages.updated"))
      expect(recipe.reload.name).to eq("Updated name")
      expect(recipe.portion_size_grams).to eq(150)
    end

    it "adds recipe images" do
      patch :update, params: {
        id: recipe.id,
        recipe: {
          name: recipe.name,
          ingredients: recipe.ingredients,
          portion_size_grams: recipe.portion_size_grams,
          images: [ uploaded_recipe_image ]
        }
      }

      expect(response).to redirect_to(patient_recipe_path(recipe))
      expect(recipe.reload.images.count).to eq(1)
      expect(recipe.images.first.file).to be_attached
    end

    it "re-renders the edit form when validation fails" do
      patch :update, params: {
        id: recipe.id,
        recipe: {
          name: "",
          ingredients: recipe.ingredients,
          portion_size_grams: 150
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
          portion_size_grams: 150
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
