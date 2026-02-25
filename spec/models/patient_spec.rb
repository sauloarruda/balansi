require "rails_helper"

RSpec.describe Patient, type: :model do
  describe "validations" do
    it "is valid with user and professional" do
      patient = build(:patient)
      expect(patient).to be_valid
    end

    it "requires user" do
      patient = build(:patient, user: nil)
      expect(patient).not_to be_valid
      expect(patient.errors[:user]).to be_present
    end

    it "requires professional" do
      patient = build(:patient, professional: nil)
      expect(patient).not_to be_valid
      expect(patient.errors[:professional]).to be_present
    end

    it "validates one patient profile per user" do
      user = create(:user)
      create(:patient, user: user)

      duplicate_patient = build(:patient, user: user)
      expect(duplicate_patient).not_to be_valid
      expect(duplicate_patient.errors[:user_id].join(" ")).to include("already has a patient record")
    end

    it "allows same professional for different users" do
      professional = create(:professional)
      patient1 = create(:patient, user: create(:user), professional: professional)
      patient2 = create(:patient, user: create(:user), professional: professional)

      expect(patient1).to be_valid
      expect(patient2).to be_valid
    end

    it "does not allow weight_kg below minimum" do
      patient = build(:patient, weight_kg: 19.99)
      expect(patient).not_to be_valid
      expect(patient.errors[:weight_kg]).to be_present
    end

    it "does not allow weight_kg above decimal column range" do
      patient = build(:patient, weight_kg: 1000)
      expect(patient).not_to be_valid
      expect(patient.errors[:weight_kg]).to be_present
    end

    it "does not allow height_cm below minimum" do
      patient = build(:patient, height_cm: 99.99)
      expect(patient).not_to be_valid
      expect(patient.errors[:height_cm]).to be_present
    end

    it "does not allow height_cm above decimal column range" do
      patient = build(:patient, height_cm: 1000)
      expect(patient).not_to be_valid
      expect(patient.errors[:height_cm]).to be_present
    end

    it "validates gender enum values" do
      patient = build(:patient, gender: "invalid")
      expect(patient).not_to be_valid
      expect(patient.errors[:gender]).to be_present
    end

    it "validates phone_e164 format when present" do
      patient = build(:patient, phone_e164: "123456")
      expect(patient).not_to be_valid
      expect(patient.errors[:phone_e164]).to be_present
    end
  end

  describe "associations" do
    it "belongs to user" do
      patient = create(:patient)
      expect(patient.user).to be_present
    end

    it "belongs to professional" do
      patient = create(:patient)
      expect(patient.professional).to be_present
    end

    it "has many shared professionals through accesses" do
      patient = create(:patient)
      shared_professional = create(:professional)
      create(:patient_professional_access,
        patient: patient,
        professional: shared_professional,
        granted_by_patient_user: patient.user)

      expect(patient.shared_professionals).to include(shared_professional)
    end
  end

  describe "personal profile" do
    it "requires mandatory personal fields in patient_personal_profile context" do
      patient = build(
        :patient,
        gender: nil,
        birth_date: nil,
        weight_kg: nil,
        height_cm: nil,
        phone_e164: nil
      )

      expect(patient.valid?(:patient_personal_profile)).to be false
      expect(patient.errors[:gender]).to be_present
      expect(patient.errors[:birth_date]).to be_present
      expect(patient.errors[:weight_kg]).to be_present
      expect(patient.errors[:height_cm]).to be_present
      expect(patient.errors[:phone_e164]).to be_present
    end

    it "is complete only when required fields are present and profile_completed_at is set" do
      complete_patient = build(:patient)
      incomplete_patient = build(:patient, :incomplete_profile)

      expect(complete_patient.personal_profile_completed?).to be true
      expect(incomplete_patient.personal_profile_completed?).to be false
    end
  end

  describe "age and BMI helpers" do
    include ActiveSupport::Testing::TimeHelpers

    it "returns age in years and months from birth_date" do
      travel_to(Date.new(2026, 6, 15)) do
        patient = build(:patient, birth_date: Date.new(1990, 1, 1))
        expect(patient.age_in_years_and_months).to eq({ years: 36, months: 5 })
      end
    end

    it "returns nil for age when birth_date is blank" do
      patient = build(:patient, birth_date: nil)
      expect(patient.age_in_years_and_months).to be_nil
    end

    it "computes BMI from weight and height" do
      patient = build(:patient, weight_kg: 70, height_cm: 170)
      expect(patient.bmi).to eq(24.2)
    end

    it "returns nil for BMI when weight or height missing" do
      expect(build(:patient, weight_kg: nil, height_cm: 170).bmi).to be_nil
      expect(build(:patient, weight_kg: 70, height_cm: nil).bmi).to be_nil
    end

    it "returns correct bmi_category" do
      expect(build(:patient, weight_kg: 50, height_cm: 170).bmi_category).to eq(:underweight)
      expect(build(:patient, weight_kg: 70, height_cm: 170).bmi_category).to eq(:normal)
      expect(build(:patient, weight_kg: 80, height_cm: 170).bmi_category).to eq(:overweight)
      expect(build(:patient, weight_kg: 95, height_cm: 170).bmi_category).to eq(:obesity_1)
    end

    it "returns normal_bmi_weight_range for height" do
      patient = build(:patient, height_cm: 170)
      min, max = patient.normal_bmi_weight_range
      expect(min).to eq(53.5)
      expect(max).to eq(72.0)
    end

    it "returns weight_difference_to_normal_kg (positive = to lose)" do
      patient = build(:patient, weight_kg: 85, height_cm: 170)
      expect(patient.weight_difference_to_normal_kg).to eq(13.0)
    end

    it "returns weight_difference_to_normal_kg (negative = to gain)" do
      patient = build(:patient, weight_kg: 50, height_cm: 170)
      expect(patient.weight_difference_to_normal_kg).to eq(-3.5)
    end

    it "returns nil for weight_difference when in normal range" do
      patient = build(:patient, weight_kg: 65, height_cm: 170)
      expect(patient.weight_difference_to_normal_kg).to be_nil
    end
  end
end
