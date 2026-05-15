module Patients
  class RecipesController < ApplicationController
    before_action :set_recipe, only: [ :show, :edit, :update, :destroy ]

    def index
      @recipes = current_patient.recipes.includes(images: image_includes).order(created_at: :desc)
    end

    def show; end

    def new
      @return_to = safe_return_to
      @recipe = current_patient.recipes.build(recipe_params_from_query)
    end

    def create
      @return_to = safe_return_to
      @recipe = current_patient.recipes.build

      if save_recipe
        redirect_to(created_recipe_return_to.presence || patient_recipe_path(@recipe), notice: t("patient.recipes.messages.created"))
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

    def recipe_params_from_query
      return {} if params[:recipe].blank?

      params.require(:recipe).permit(:name)
    end

    def safe_return_to
      return if params[:return_to].blank?

      url_from(params[:return_to].presence)
    end

    def created_recipe_return_to
      return if @return_to.blank?

      uri = URI.parse(@return_to)
      query_params = Rack::Utils.parse_nested_query(uri.query)
      query_params.merge!(
        "created_recipe_mention_id" => @recipe.id,
        "created_recipe_mention_name" => @recipe.name,
        "created_recipe_mention_portion_size_grams" => @recipe.portion_size_grams,
        "created_recipe_mention_calories_per_portion" => @recipe.calories,
        "created_recipe_mention_proteins_per_portion" => @recipe.proteins,
        "created_recipe_mention_carbs_per_portion" => @recipe.carbs,
        "created_recipe_mention_fats_per_portion" => @recipe.fats
      )
      uri.query = Rack::Utils.build_query(query_params)
      uri.to_s
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
