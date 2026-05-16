module Patients
  module Recipes
    class SearchController < ApplicationController
      def index
        render json: search_results.map { |recipe| recipe_payload(recipe) }
      end

      private

      def search_results
        ::Recipes::SearchInteraction.run!(
          patient: current_patient,
          query: params[:q].to_s,
          recipe_id: params[:recipe_id].to_s,
          recent: recent_results?
        )
      end

      def recent_results?
        ActiveModel::Type::Boolean.new.cast(params[:recent])
      end

      def recipe_payload(recipe)
        {
          id: recipe.id,
          name: recipe.name,
          thumbnail_url: thumbnail_url_for(recipe),
          calories_per_portion: recipe.calories_per_portion,
          proteins_per_portion: recipe.proteins_per_portion,
          carbs_per_portion: recipe.carbs_per_portion,
          fats_per_portion: recipe.fats_per_portion,
          portion_size_grams: recipe.portion_size_grams.to_f
        }
      end

      def thumbnail_url_for(recipe)
        image = recipe.images.first
        return nil unless image&.file&.attached?

        url_for(image.thumbnail)
      end
    end
  end
end
