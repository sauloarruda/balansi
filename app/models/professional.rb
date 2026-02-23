class Professional < ApplicationRecord
  belongs_to :user

  has_many :owned_patients, class_name: "Patient", dependent: :restrict_with_error
  has_many :patient_professional_accesses, dependent: :destroy
  has_many :shared_patients, through: :patient_professional_accesses, source: :patient

  validates :user_id, uniqueness: true
end
