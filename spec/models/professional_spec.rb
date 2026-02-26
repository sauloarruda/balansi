require "rails_helper"

RSpec.describe Professional, type: :model do
  describe "associations" do
    it "belongs to user" do
      professional = create(:professional)
      expect(professional.user).to be_present
    end

    it "has many owned patients" do
      professional = create(:professional)
      patient = create(:patient, professional: professional)

      expect(professional.owned_patients).to include(patient)
    end
  end

  describe "validations" do
    it "enforces one professional profile per user" do
      user = create(:user)
      create(:professional, user: user)

      duplicate = build(:professional, user: user)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:user_id]).to be_present
    end
  end

  describe "#linked_patients" do
    it "returns owned and shared patients" do
      professional = create(:professional)
      owned_patient = create(:patient, professional: professional)
      shared_patient = create(:patient)
      create(:patient_professional_access, professional: professional, patient: shared_patient)
      unrelated_patient = create(:patient)

      linked_ids = professional.linked_patients.pluck(:id)

      expect(linked_ids).to include(owned_patient.id, shared_patient.id)
      expect(linked_ids).not_to include(unrelated_patient.id)
    end

    it "does not duplicate patients that are both owned and shared" do
      professional = create(:professional)
      patient = create(:patient, professional: professional)
      create(:patient_professional_access, professional: professional, patient: patient)

      linked_ids = professional.linked_patients.where(id: patient.id).pluck(:id)

      expect(linked_ids.size).to eq(1)
    end

    it "returns an empty relation when no patients are linked" do
      professional = create(:professional)

      expect(professional.linked_patients).to be_empty
    end
  end

  describe "#owner_of?" do
    it "returns true for a patient owned by the professional" do
      professional = create(:professional)
      patient = create(:patient, professional: professional)

      expect(professional.owner_of?(patient)).to be(true)
    end

    it "returns false for a patient owned by another professional" do
      professional = create(:professional)
      patient = create(:patient)

      expect(professional.owner_of?(patient)).to be(false)
    end
  end

  describe "#can_access?" do
    it "returns true when the professional owns the patient" do
      professional = create(:professional)
      patient = create(:patient, professional: professional)

      expect(professional.can_access?(patient)).to be(true)
    end

    it "returns true when the patient is shared with the professional" do
      professional = create(:professional)
      patient = create(:patient)
      create(:patient_professional_access, professional: professional, patient: patient)

      expect(professional.can_access?(patient)).to be(true)
    end

    it "returns false when the professional neither owns nor has shared access" do
      professional = create(:professional)
      patient = create(:patient)

      expect(professional.can_access?(patient)).to be(false)
    end
  end
end
