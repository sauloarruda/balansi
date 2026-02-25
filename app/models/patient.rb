class Patient < ApplicationRecord
  include BmiCalculations

  DECIMAL_5_2_MAX = 999.99
  WEIGHT_KG_MIN = 20
  WEIGHT_KG_MAX = DECIMAL_5_2_MAX
  HEIGHT_CM_MIN = 100
  HEIGHT_CM_MAX = DECIMAL_5_2_MAX
  PERSONAL_PROFILE_REQUIRED_FIELDS = %i[
    gender
    birth_date
    weight_kg
    height_cm
    phone_e164
  ].freeze
  E164_PHONE_FORMAT = /\A\+[1-9]\d{7,14}\z/

  belongs_to :user
  belongs_to :professional
  has_many :journals, dependent: :destroy
  has_many :patient_professional_accesses, dependent: :destroy
  has_many :shared_professionals, through: :patient_professional_accesses, source: :professional

  enum :gender, { male: "male", female: "female" }, validate: { allow_nil: true }

  validates :user_id, uniqueness: { message: "already has a patient record" }
  validates :phone_e164,
    length: { maximum: 20 },
    format: { with: E164_PHONE_FORMAT, message: "must be in E.164 format" },
    allow_nil: true
  validates :weight_kg,
    numericality: { greater_than_or_equal_to: WEIGHT_KG_MIN, less_than_or_equal_to: WEIGHT_KG_MAX },
    allow_nil: true
  validates :height_cm,
    numericality: { greater_than_or_equal_to: HEIGHT_CM_MIN, less_than_or_equal_to: HEIGHT_CM_MAX },
    allow_nil: true
  validates :birth_date,
    comparison: { less_than_or_equal_to: -> { Date.current }, message: :not_in_future },
    allow_nil: true
  validates :daily_calorie_goal, numericality: { greater_than: 0, less_than: 50_000 }, allow_nil: true
  validates :bmr, numericality: { greater_than: 0, less_than: 10_000 }, allow_nil: true
  validates :steps_goal, numericality: { greater_than: 0, less_than: 100_000 }, allow_nil: true
  validates :hydration_goal, numericality: { greater_than: 0, less_than: 20_000 }, allow_nil: true
  with_options on: :patient_personal_profile do
    validates :gender, :birth_date, :weight_kg, :height_cm, :phone_e164, presence: true
  end

  validate :professional_id_immutable, on: :update

  def personal_profile_completed?
    profile_completed_at.present? && personal_profile_fields_present?
  end

  def personal_profile_fields_present?
    PERSONAL_PROFILE_REQUIRED_FIELDS.all? { |field| public_send(field).present? }
  end

  # Returns { years: N, months: N } or nil if birth_date is blank or in the future.
  def age_in_years_and_months
    return nil if birth_date.blank?

    today = Time.zone.today
    return nil if birth_date > today

    months = (today.year * 12 + today.month) - (birth_date.year * 12 + birth_date.month)
    months -= 1 if today.day < birth_date.day
    { years: months / 12, months: months % 12 }
  end

  private

  def professional_id_immutable
    return unless persisted? && will_save_change_to_professional_id?

    errors.add(:professional_id, "cannot be changed once set")
  end
end
