require "rails_helper"

RSpec.describe Image, type: :model do
  include ActiveJob::TestHelper

  around do |example|
    clear_enqueued_jobs
    clear_performed_jobs
    example.run
    clear_enqueued_jobs
    clear_performed_jobs
  end

  describe "associations" do
    it "belongs to recipe" do
      image = create(:image)

      expect(image.recipe).to be_present
    end
  end

  describe "validations" do
    it "requires an attached file" do
      image = build(:image)
      image.file.detach

      expect(image).not_to be_valid
      expect(image.errors[:file]).to be_present
    end
  end

  describe "variants" do
    it "defines optimized display variants using resize_to_limit" do
      image = create(:image)

      expect(image.file.variant(:thumbnail).variation.transformations).to include(resize_to_limit: [ 100, 100 ])
      expect(image.file.variant(:standard).variation.transformations).to include(resize_to_limit: [ 600, 400 ])
      expect(image.file.variant(:large).variation.transformations).to include(resize_to_limit: [ 1200, 800 ])
    end

    it "preprocesses display variants asynchronously" do
      named_variants = described_class.attachment_reflections["file"].named_variants

      expect(named_variants[:thumbnail].preprocessed).to be true
      expect(named_variants[:standard].preprocessed).to be true
      expect(named_variants[:large].preprocessed).to be true
      expect { create(:image) }.to have_enqueued_job(ActiveStorage::TransformJob).exactly(3).times
    end

    it "knows whether a variant has already been processed" do
      image = create(:image)

      expect(image.variant_ready?(:standard)).to be false

      mark_variant_processed(image, :standard)

      expect(image.variant_ready?(:standard)).to be true
    end
  end
end
