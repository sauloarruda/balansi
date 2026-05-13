module Patients
  class RecipesController < ApplicationController
    before_action :set_recipe, only: [ :show, :edit, :update, :destroy ]

    def index
      @recipes = current_patient.recipes.includes(images: image_includes).order(created_at: :desc)
    end

    def show; end

    def new
      @recipe = current_patient.recipes.build
    end

    def create
      @recipe = current_patient.recipes.build(recipe_params)

      if save_recipe_with_images
        redirect_to patient_recipe_path(@recipe), notice: t("patient.recipes.messages.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      @recipe.assign_attributes(recipe_params)

      if save_recipe_with_images
        redirect_to patient_recipe_path(@recipe), notice: t("patient.recipes.messages.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @recipe.destroy!

      redirect_to patient_recipes_path,
        status: :see_other,
        notice: t("patient.recipes.messages.deleted")
    end

    private

    def set_recipe
      @recipe = current_patient.recipes.includes(images: image_includes).find(params[:id])
    end

    def image_includes
      { file_attachment: { blob: { variant_records: { image_attachment: :blob } } } }
    end

    def recipe_params
      params.require(:recipe).permit(
        :name,
        :ingredients,
        :instructions,
        :portion_size_grams,
        :calories,
        :proteins,
        :carbs,
        :fats
      )
    end

    def attach_images
      Array(params.dig(:recipe, :images)).compact_blank.each.with_index(@recipe.images.count) do |uploaded_file, position|
        @recipe.images.create!(file: uploaded_file, position: position)
      end
    end

    def save_recipe_with_images
      Recipe.transaction do
        @recipe.save.tap do |saved|
          attach_images if saved
        end
      end
    end
  end
end
