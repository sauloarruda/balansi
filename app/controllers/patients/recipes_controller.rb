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
      @recipe = current_patient.recipes.build

      if save_recipe
        redirect_to patient_recipe_path(@recipe), notice: t("patient.recipes.messages.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if save_recipe
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

    def save_recipe
      result = ::Recipes::SaveInteraction.run(
        recipe: @recipe,
        user: current_user,
        attributes: recipe_params,
        images: recipe_images,
        calculate_macros_with_ai: calculate_macros_with_ai?
      )

      result.valid?
    end

    def recipe_images
      Array(params.dig(:recipe, :images)).compact_blank
    end

    def calculate_macros_with_ai?
      ActiveModel::Type::Boolean.new.cast(params.dig(:recipe, :calculate_macros_with_ai))
    end
  end
end
