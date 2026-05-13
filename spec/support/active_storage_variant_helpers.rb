require "base64"
require "stringio"

module ActiveStorageVariantHelpers
  PROCESSED_VARIANT_PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
  ).freeze

  def mark_variant_processed(record, variant_name)
    variant = record.file.variant(variant_name)
    variant_record = record.file.blob.variant_records.find_or_create_by!(
      variation_digest: variant.variation.digest
    )

    return variant_record if variant_record.image.attached?

    variant_record.image.attach(
      io: StringIO.new(PROCESSED_VARIANT_PNG),
      filename: "#{variant_name}.png",
      content_type: "image/png"
    )

    variant_record
  end
end

RSpec.configure do |config|
  config.include ActiveStorageVariantHelpers
end
