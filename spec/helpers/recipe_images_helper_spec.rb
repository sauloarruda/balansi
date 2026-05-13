require "rails_helper"

RSpec.describe RecipeImagesHelper, type: :helper do
  describe "#recipe_image_tag" do
    it "renders the processing placeholder while the variant is not ready" do
      image = create(:image)

      tag = helper.recipe_image_tag(image, :standard, alt: "Recipe", class: "recipe-image")

      expect(tag).to include("image-processing")
      expect(tag).to include(%(alt="#{I18n.t('patient.recipes.images.processing')}"))
      expect(tag).to include(%(class="recipe-image"))
      expect(tag).to include(%(data-controller="processing-image"))
      expect(tag).to include("data-processing-image-src-value=")
      expect(tag).to include(%(data-processing-image-interval-value="3000"))
    end

    it "renders the processed variant when it is ready" do
      image = create(:image)
      mark_variant_processed(image, :standard)

      tag = helper.recipe_image_tag(image, :standard, alt: "Recipe", class: "recipe-image")

      expect(tag).to include("rails/active_storage/representations")
      expect(tag).to include(%(alt="Recipe"))
      expect(tag).to include(%(class="recipe-image"))
    end
  end
end
