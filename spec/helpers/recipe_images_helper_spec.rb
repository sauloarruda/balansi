require "rails_helper"

RSpec.describe RecipeImagesHelper, type: :helper do
  describe "#recipe_image_tag" do
    it "renders the processing placeholder while the variant is not ready" do
      image = create(:image)

      tag = helper.recipe_image_tag(image, :standard, alt: "Recipe", class: "recipe-image")

      expect(tag).to include("image-processing")
      expect(tag).to include(%(alt="#{I18n.t('patient.recipes.images.processing')}"))
      expect(tag).to include(%(class="recipe-image"))
    end

    it "renders the processed variant when it is ready" do
      image = create(:image)
      image.file.variant(:standard).processed

      tag = helper.recipe_image_tag(image, :standard, alt: "Recipe", class: "recipe-image")

      expect(tag).to include("rails/active_storage/representations")
      expect(tag).to include(%(alt="Recipe"))
      expect(tag).to include(%(class="recipe-image"))
    end
  end
end
