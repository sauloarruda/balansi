require "rails_helper"

RSpec.describe PatientProfessionalAccess, type: :model do
  describe "associations" do
    it "belongs to patient" do
      access = create(:patient_professional_access)
      expect(access.patient).to be_present
    end

    it "belongs to professional" do
      access = create(:patient_professional_access)
      expect(access.professional).to be_present
    end

    it "belongs to granted_by_patient_user" do
      access = create(:patient_professional_access)
      expect(access.granted_by_patient_user).to be_present
    end
  end

  describe "validations" do
    it "enforces unique patient/professional pair" do
      patient = create(:patient)
      professional = create(:professional)
      create(:patient_professional_access,
        patient: patient,
        professional: professional,
        granted_by_patient_user: patient.user)

      duplicate = build(:patient_professional_access,
        patient: patient,
        professional: professional,
        granted_by_patient_user: patient.user)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:patient_id].join(" ")).to include("already shared with this professional")
    end
  end
end
