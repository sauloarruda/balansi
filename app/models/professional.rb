class Professional < ApplicationRecord
  belongs_to :user

  has_many :owned_patients, class_name: "Patient", dependent: :restrict_with_error
  has_many :patient_professional_accesses, dependent: :destroy
  has_many :shared_patients, through: :patient_professional_accesses, source: :patient

  validates :user_id, uniqueness: true

  def linked_patients
    # include user by default to avoid n+1 when callers iterate over patient.user
    base = Patient.includes(:user)
    base.where(professional_id: id).or(
      base.where(id: patient_professional_accesses.select(:patient_id))
    )
  end

  def owner_of?(patient)
    patient.professional_id == id
  end

  def can_access?(patient)
    owner_of?(patient) || shared_patients.exists?(id: patient.id)
  end
end
