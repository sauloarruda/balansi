class Meal < ApplicationRecord
  extend Enumerize

  MEAL_TYPES = %w[breakfast lunch snack dinner].freeze
  FEELING_POSITIVE = 1
  FEELING_NEGATIVE = 0

  belongs_to :journal

  enumerize :status, in: {
    pending_llm: "pending_llm",
    pending_patient: "pending_patient",
    confirmed: "confirmed"
  }, default: :pending_llm, predicates: true, scope: true

  validates :meal_type, presence: true, inclusion: { in: MEAL_TYPES }
  validates :description, presence: true, length: { maximum: 500 }
  validates :proteins, numericality: { greater_than_or_equal_to: 0, less_than: 10_000 }, allow_nil: true
  validates :carbs, numericality: { greater_than_or_equal_to: 0, less_than: 10_000 }, allow_nil: true
  validates :fats, numericality: { greater_than_or_equal_to: 0, less_than: 10_000 }, allow_nil: true
  validates :calories, numericality: { greater_than: 0, less_than: 50_000 }, allow_nil: true
  validates :gram_weight, numericality: { greater_than: 0, less_than: 100_000 }, allow_nil: true
  validates :feeling, inclusion: { in: [ FEELING_POSITIVE, FEELING_NEGATIVE ] }, allow_nil: true

  scope :pending, -> { where(status: [ "pending_llm", "pending_patient" ]) }
  scope :by_meal_type, ->(type) { where(meal_type: type) }

  def pending?
    pending_llm? || pending_patient?
  end

  def feeling_positive?
    feeling == FEELING_POSITIVE
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
