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

    it "does not allow height_cm below minimum" do
      patient = build(:patient, height_cm: 99.99)
      expect(patient).not_to be_valid
      expect(patient.errors[:height_cm]).to be_present
    end

    it "validates gender enum values" do
      patient = build(:patient, gender: "invalid")
      expect(patient).not_to be_valid
      expect(patient.errors[:gender]).to be_present
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
end
