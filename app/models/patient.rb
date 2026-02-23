class Patient < ApplicationRecord
  belongs_to :user
  belongs_to :professional
  has_many :journals, dependent: :destroy
  has_many :patient_professional_accesses, dependent: :destroy
  has_many :shared_professionals, through: :patient_professional_accesses, source: :professional

  enum :gender, { male: "male", female: "female" }, validate: { allow_nil: true }

  validates :user_id, uniqueness: { message: "already has a patient record" }
  validates :phone_e164, length: { maximum: 20 }, allow_nil: true
  validates :weight_kg, numericality: { greater_than_or_equal_to: 20 }, allow_nil: true
  validates :height_cm, numericality: { greater_than_or_equal_to: 100 }, allow_nil: true
  validates :daily_calorie_goal, numericality: { greater_than: 0, less_than: 50_000 }, allow_nil: true
  validates :bmr, numericality: { greater_than: 0, less_than: 10_000 }, allow_nil: true
  validates :steps_goal, numericality: { greater_than: 0, less_than: 100_000 }, allow_nil: true
  validates :hydration_goal, numericality: { greater_than: 0, less_than: 20_000 }, allow_nil: true

  validate :professional_id_immutable, on: :update

  private

  def professional_id_immutable
    return unless persisted? && will_save_change_to_professional_id?

    errors.add(:professional_id, "cannot be changed once set")
  end
end
