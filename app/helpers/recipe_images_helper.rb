module RecipeImagesHelper
  def recipe_image_tag(image, variant_name, alt:, **options)
    if image.variant_ready?(variant_name)
      image_tag image.public_send(variant_name), alt: alt, **options
    else
      image_tag "image-processing.svg",
        alt: t("patient.recipes.images.processing"),
        **options
    end
  end
end
