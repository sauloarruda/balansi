class Professional < ApplicationRecord
  belongs_to :user

  has_many :owned_patients, class_name: "Patient", dependent: :restrict_with_error
  has_many :patient_professional_accesses, dependent: :destroy
  has_many :shared_patients, through: :patient_professional_accesses, source: :patient

  validates :user_id, uniqueness: true
  INVITE_CODE_FORMAT = /\A[A-Z0-9]{6}\z/

  validates :invite_code, presence: true, uniqueness: true, length: { is: 6 },
                          format: { with: INVITE_CODE_FORMAT }

  before_validation :generate_invite_code, on: :create

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

  def admin?
    user.admin?
  end

  def can_access?(patient)
    return true if admin?

    owner_of?(patient) || shared_patients.exists?(id: patient.id)
  end

  private

  def generate_invite_code
    return if invite_code.present?

    loop do
      self.invite_code = SecureRandom.alphanumeric(6).upcase
      break unless Professional.exists?(invite_code: invite_code)
    end
  end
end
