class Patient < ApplicationRecord
  # Associations
  belongs_to :user
  # belongs_to :professional  # Uncomment when Professional model is created

  # Validations
  validates :user_id, uniqueness: { scope: :professional_id, message: "already has a patient record for this professional" }
end
