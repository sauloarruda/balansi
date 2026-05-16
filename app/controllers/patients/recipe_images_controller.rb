module Patients
  class RecipeImagesController < ApplicationController
    def destroy
      recipe = current_patient.recipes.kept.find(params[:recipe_id])
      image = recipe.images.find(params[:id])

      image.destroy!

      redirect_back fallback_location: edit_patient_recipe_path(recipe),
        status: :see_other,
        notice: t("patient.recipes.messages.image_deleted")
    end
  end
end
