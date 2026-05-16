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

    it "does not list discarded recipes" do
      kept_recipe = create(:recipe, patient: patient, name: "Visible soup")
      discarded_recipe = create(:recipe, patient: patient, name: "Hidden soup")
      discarded_recipe.discard!

      get :index

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(kept_recipe.name)
      expect(response.body).not_to include(discarded_recipe.name)
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

    it "does not show discarded recipes" do
      recipe = create(:recipe, patient: patient, name: "Discarded cake")
      recipe.discard!

      get :show, params: { id: recipe.id }

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(recipe.name)
    end
  end

  describe "GET #new" do
    it "renders the new recipe form" do
      get :new

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("recipe[name]")
      expect(response.body).to include(I18n.t("patient.recipes.form.calculate_macros_with_ai"))
      expect(response.body).to include(%(name="recipe[calculate_macros_with_ai]"))
      expect(response.body).to include(%(checked="checked"))
      expect(response.body).to include(%(id="recipe_manual_nutrition_fields"))
      expect(response.body).to include(%(hidden=""))
      expect(response.body).to include(%(name="recipe[calories]"))
      expect(response.body).to include(%(disabled="disabled"))
      expect(response.body).to include(I18n.t("patient.recipes.actions.create"))
    end

    it "prefills the recipe name and keeps a local return path" do
      return_to = journal_path(date: Date.current.iso8601)

      get :new, params: { return_to: return_to, recipe: { name: "Bolo" } }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(value="Bolo"))
      expect(response.body).to include(%(name="return_to"))
      expect(response.body).to include(return_to)
      expect(response.body).to include(I18n.t("patient.recipes.actions.back"))
    end

    it "ignores external return paths" do
      get :new, params: { return_to: "https://example.com/outside" }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("https://example.com/outside")
      expect(response.body).to include(I18n.t("patient.recipes.actions.back_to_recipes"))
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
      allow(Recipes::AnalyzeNutritionInteraction).to receive(:run)

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
      expect(Recipes::AnalyzeNutritionInteraction).not_to have_received(:run)
    end

    it "redirects to a local return path after creating a recipe from another flow" do
      allow(Recipes::AnalyzeNutritionInteraction).to receive(:run)
      return_to = edit_journal_meal_path(journal_date: Date.current.iso8601, id: 123)

      post :create, params: { return_to: return_to, recipe: valid_params }

      redirect_uri = URI.parse(response.location)
      redirect_params = Rack::Utils.parse_query(redirect_uri.query)
      expect(redirect_uri.path).to eq(return_to)
      expect(redirect_params["created_recipe_mention_id"]).to eq(patient.recipes.last.id.to_s)
      expect(redirect_params).not_to include(
        "created_recipe_mention_name",
        "created_recipe_mention_portion_size_grams",
        "created_recipe_mention_calories_per_portion",
        "created_recipe_mention_proteins_per_portion",
        "created_recipe_mention_carbs_per_portion",
        "created_recipe_mention_fats_per_portion"
      )
      expect(flash[:notice]).to eq(I18n.t("patient.recipes.messages.created"))
    end

    it "ignores external return paths after creating a recipe" do
      allow(Recipes::AnalyzeNutritionInteraction).to receive(:run)

      post :create, params: { return_to: "https://example.com/outside", recipe: valid_params }

      expect(response).to redirect_to(patient_recipe_path(patient.recipes.last))
    end

    it "creates a recipe with AI nutrition when macro values are missing" do
      allow(Recipes::AnalyzeNutritionInteraction).to receive(:run) do |recipe:, persist:, **|
        recipe.assign_attributes(calories: 430, proteins: 25.5, carbs: 56.25, fats: 10.75)
        instance_double(ActiveInteraction::Base, valid?: true)
      end

      expect do
        post :create, params: {
          recipe: valid_params.except(:calories, :proteins, :carbs, :fats).merge(calculate_macros_with_ai: "1")
        }
      end.to change { patient.recipes.count }.by(1)

      recipe = patient.recipes.last
      expect(recipe.calories).to eq(430)
      expect(recipe.proteins).to eq(25.5)
      expect(recipe.carbs).to eq(56.25)
      expect(recipe.fats).to eq(10.75)
      expect(response).to redirect_to(patient_recipe_path(recipe))
      expect(Recipes::AnalyzeNutritionInteraction).to have_received(:run).with(
        recipe: an_instance_of(Recipe),
        user_id: patient_user.id,
        user_language: patient_user.language,
        persist: false
      )
    end

    it "re-renders the form without creating the recipe when AI nutrition fails" do
      errors = ActiveModel::Errors.new(Recipe.new)
      errors.add(:base, I18n.t("patient.recipes.errors.nutrition_analysis_unavailable"))
      allow(Recipes::AnalyzeNutritionInteraction).to receive(:run).and_return(
        instance_double(ActiveInteraction::Base, valid?: false, errors: errors)
      )

      expect do
        post :create, params: {
          recipe: valid_params.except(:calories, :proteins, :carbs, :fats).merge(calculate_macros_with_ai: "1")
        }
      end.not_to change { patient.recipes.count }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("patient.recipes.errors.nutrition_analysis_unavailable"))
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

    it "rolls back the recipe when image upload fails" do
      allow_any_instance_of(Recipes::SaveInteraction).to receive(:attach_images).and_raise(StandardError, "attach failed")

      expect do
        expect do
          post :create, params: { recipe: valid_params.merge(images: [ uploaded_recipe_image ]) }
        end.to raise_error(StandardError, "attach failed")
      end.not_to change { patient.recipes.count }
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

    it "does not render the edit form for discarded recipes" do
      recipe = create(:recipe, patient: patient, name: "Discarded recipe")
      recipe.discard!

      get :edit, params: { id: recipe.id }

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(recipe.name)
    end
  end

  describe "PATCH #update" do
    let!(:recipe) { create(:recipe, patient: patient, name: "Original name") }

    it "updates a recipe owned by the current patient" do
      allow(Recipes::AnalyzeNutritionInteraction).to receive(:run)

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
      expect(Recipes::AnalyzeNutritionInteraction).not_to have_received(:run)
    end

    it "allows manual edits to AI-generated nutrition values without reanalysis" do
      allow(Recipes::AnalyzeNutritionInteraction).to receive(:run)

      patch :update, params: {
        id: recipe.id,
        recipe: {
          name: recipe.name,
          ingredients: recipe.ingredients,
          portion_size_grams: recipe.portion_size_grams,
          calories: 510,
          proteins: 31.5,
          carbs: 62.25,
          fats: 14.75
        }
      }

      expect(response).to redirect_to(patient_recipe_path(recipe))
      expect(recipe.reload.calories).to eq(510)
      expect(recipe.proteins).to eq(31.5)
      expect(recipe.carbs).to eq(62.25)
      expect(recipe.fats).to eq(14.75)
      expect(Recipes::AnalyzeNutritionInteraction).not_to have_received(:run)
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

    it "rolls back recipe updates when image upload fails" do
      allow_any_instance_of(Recipes::SaveInteraction).to receive(:attach_images).and_raise(StandardError, "attach failed")

      expect do
        expect do
          patch :update, params: {
            id: recipe.id,
            recipe: {
              name: "Updated name",
              ingredients: recipe.ingredients,
              portion_size_grams: recipe.portion_size_grams,
              images: [ uploaded_recipe_image ]
            }
          }
        end.to raise_error(StandardError, "attach failed")
      end.not_to change { recipe.reload.name }
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

    it "does not update discarded recipes" do
      recipe.discard!

      patch :update, params: {
        id: recipe.id,
        recipe: {
          name: "Updated discarded",
          ingredients: recipe.ingredients,
          portion_size_grams: 150
        }
      }

      expect(response).to have_http_status(:not_found)
      expect(recipe.reload.name).to eq("Original name")
    end
  end

  describe "DELETE #destroy" do
    it "soft deletes a recipe owned by the current patient" do
      recipe = create(:recipe, patient: patient)

      expect do
        delete :destroy, params: { id: recipe.id }
      end.to change { patient.recipes.kept.count }.by(-1)

      expect(response).to redirect_to(patient_recipes_path)
      expect(response).to have_http_status(:see_other)
      expect(flash[:notice]).to eq(I18n.t("patient.recipes.messages.archived"))
      expect(recipe.reload).to be_discarded
      expect(Recipe.exists?(recipe.id)).to be true
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
