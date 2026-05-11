module Patients
  class RecipesController < ApplicationController
    before_action :set_recipe, only: [ :show, :edit, :update, :destroy ]

    def index
      @recipes = current_patient.recipes.order(created_at: :desc)
    end

    def show; end

    def new
      @recipe = current_patient.recipes.build
    end

    def create
      @recipe = current_patient.recipes.build(recipe_params)

      if @recipe.save
        redirect_to patient_recipe_path(@recipe), notice: t("patient.recipes.messages.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @recipe.update(recipe_params)
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
      @recipe = current_patient.recipes.find(params[:id])
    end

    def recipe_params
      params.require(:recipe).permit(
        :name,
        :ingredients,
        :instructions,
        :yield_portions,
        :calories,
        :proteins,
        :carbs,
        :fats
      )
    end
  end
end
