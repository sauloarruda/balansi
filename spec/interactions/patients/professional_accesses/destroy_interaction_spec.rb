require "rails_helper"

RSpec.describe Patients::ProfessionalAccesses::DestroyInteraction do
  let(:professional) { create(:professional) }
  let(:patient) { create(:patient, professional: professional) }
  let(:other_pro) { create(:professional) }
  let!(:access) do
    create(:patient_professional_access, patient: patient, professional: other_pro, granted_by_patient_user: patient.user)
  end

  subject(:run) do
    described_class.run(
      patient: patient,
      access_id: access_id
    )
  end

  context "when the access belongs to the patient" do
    let(:access_id) { access.id }

    it "destroys the access record" do
      expect { run }.to change(PatientProfessionalAccess, :count).by(-1)
    end

    it "returns the destroyed access record" do
      result = run
      expect(result.result).to be_a(PatientProfessionalAccess)
      expect(result.result.destroyed?).to be true
    end

    it "is valid" do
      expect(run).to be_valid
    end
  end

  context "when the access does not exist" do
    let(:access_id) { 0 }

    it "does not destroy any access record" do
      expect { run }.not_to change(PatientProfessionalAccess, :count)
    end

    it "adds a not found error" do
      result = run
      expect(result.errors[:base]).not_to be_empty
    end
  end

  context "when the access belongs to a different patient" do
    let(:other_patient) { create(:patient, professional: professional) }
    let!(:other_access) do
      create(:patient_professional_access, patient: other_patient, professional: other_pro, granted_by_patient_user: other_patient.user)
    end
    let(:access_id) { other_access.id }

    it "does not destroy the access record" do
      expect { run }.not_to change(PatientProfessionalAccess, :count)
    end

    it "adds a not found error" do
      result = run
      expect(result.errors[:base]).not_to be_empty
    end
  end
end
