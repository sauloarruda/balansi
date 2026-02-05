class Journal < ApplicationRecord
  extend Enumerize

  belongs_to :patient
  has_many :meals, dependent: :destroy
  has_many :exercises, dependent: :destroy

  enumerize :feeling_today, in: { bad: 1, ok: 2, good: 3 }, predicates: true, scope: true
  enumerize :sleep_quality, in: { poor: 1, good: 2, excellent: 3 }, predicates: true, scope: true
  enumerize :hydration_quality, in: { poor: 1, good: 2, excellent: 3 }, predicates: true, scope: true

  scope :closed, -> { where.not(closed_at: nil) }
  scope :open, -> { where(closed_at: nil) }
  scope :for_date, ->(date) { where(date: date) }
  scope :recent, -> { order(date: :desc) }

  validates :date, presence: true
  validates :patient_id, presence: true
  validates :score, inclusion: { in: 1..5 }, allow_nil: true
  validates :steps_count, numericality: { greater_than_or_equal_to: 0, less_than: 100_000 }, allow_nil: true
  validates :calories_consumed, numericality: { greater_than_or_equal_to: 0, less_than: 50_000 }, allow_nil: true
  validates :calories_burned, numericality: { greater_than_or_equal_to: 0, less_than: 50_000 }, allow_nil: true
  validates :date, uniqueness: { scope: :patient_id, message: "already has a journal entry for this date" }

  def closed?
    closed_at.present?
  end

  def open?
    closed_at.nil?
  end

  def editable?
    return false unless closed?

    Date.current <= date + 2.days
  end

  def confirmed_meals
    meals.status_confirmed
  end

  def confirmed_exercises
    exercises.status_confirmed
  end

  def pending_meals
    meals.pending
  end

  def pending_exercises
    exercises.pending
  end

  def has_pending_entries?
    pending_meals.exists? || pending_exercises.exists?
  end

  def calculate_calories_consumed
    confirmed_meals.sum(:calories) || 0
  end

  def calculate_calories_burned
    return 0 unless patient.bmr

    patient.bmr + confirmed_exercises.sum(:calories)
  end

  def calculate_balance
    calculate_calories_consumed - calculate_calories_burned
  end
end
