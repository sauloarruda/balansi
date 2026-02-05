class Patient < ApplicationRecord
  # Associations
  belongs_to :user
  # belongs_to :professional  # Uncomment when Professional model is created
  has_many :journals, dependent: :destroy

  # Validations
  validates :user_id, uniqueness: { scope: :professional_id, message: "already has a patient record for this professional" }
  validates :professional_id, presence: true
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
