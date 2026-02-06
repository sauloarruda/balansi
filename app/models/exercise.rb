class Exercise < ApplicationRecord
  extend Enumerize

  belongs_to :journal

  enumerize :status, in: {
    pending_llm: "pending_llm",
    pending_patient: "pending_patient",
    confirmed: "confirmed"
  }, default: :pending_llm, predicates: true, scope: true

  validates :description, presence: true, length: { maximum: 140 }
  validates :duration, numericality: { greater_than: 0, less_than: 1440 }, allow_nil: true
  validates :calories, numericality: { greater_than_or_equal_to: 0, less_than: 10_000 }, allow_nil: true
  validates :neat, numericality: { greater_than_or_equal_to: 0, less_than: 5_000 }, allow_nil: true
  validates :structured_description, length: { maximum: 255 }, allow_blank: true

  scope :pending, -> { where(status: [ "pending_llm", "pending_patient" ]) }

  def pending?
    pending_llm? || pending_patient?
  end

  def confirm!
    update!(status: :confirmed)
  end

  def mark_as_pending_patient!
    update!(status: :pending_patient)
  end

  def reprocess_with_ai!
    update!(status: :pending_llm)
  end
end
