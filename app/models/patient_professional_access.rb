class PatientProfessionalAccess < ApplicationRecord
  belongs_to :patient
  belongs_to :professional
  belongs_to :granted_by_patient_user, class_name: "User"

  validates :patient_id, uniqueness: { scope: :professional_id, message: "already shared with this professional" }
end
