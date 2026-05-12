class Image < ApplicationRecord
  belongs_to :recipe

  has_one_attached :file do |attachable|
    attachable.variant :thumbnail, resize_to_limit: [ 100, 100 ], preprocessed: true
    attachable.variant :standard, resize_to_limit: [ 600, 400 ], preprocessed: true
    attachable.variant :large, resize_to_limit: [ 1200, 800 ], preprocessed: true
  end

  validates :file, presence: true

  VARIANT_NAMES = %i[thumbnail standard large].freeze

  def thumbnail
    variant_or_file(:thumbnail)
  end

  def standard
    variant_or_file(:standard)
  end

  def large
    variant_or_file(:large)
  end

  def variant_ready?(variant_name)
    raise ArgumentError, "unknown image variant: #{variant_name}" unless VARIANT_NAMES.include?(variant_name.to_sym)
    return false unless file.attached?
    return true unless file.variable?

    variant = file.variant(variant_name)

    if ActiveStorage.track_variants
      variant.image.present?
    else
      variant.service.exist?(variant.key)
    end
  end

  private

  def variant_or_file(variant_name)
    file.variable? ? file.variant(variant_name) : file
  end
end
