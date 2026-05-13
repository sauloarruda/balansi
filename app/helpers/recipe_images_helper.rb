module RecipeImagesHelper
  def recipe_image_tag(image, variant_name, alt:, **options)
    if image.variant_ready?(variant_name)
      image_tag image.public_send(variant_name), alt: alt, **options
    else
      options[:data] = processing_image_data(options[:data], url_for(image.public_send(variant_name)))

      image_tag "image-processing.svg",
        alt: t("patient.recipes.images.processing"),
        **options
    end
  end

  private

  def processing_image_data(data, src)
    data = (data || {}).dup
    data[:controller] = [ data[:controller], "processing-image" ].compact_blank.join(" ")
    data[:processing_image_src_value] = src
    data[:processing_image_interval_value] = 3_000
    data
  end
end
