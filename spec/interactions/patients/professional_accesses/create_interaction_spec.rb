require "rails_helper"

RSpec.describe Patients::ProfessionalAccesses::CreateInteraction do
  let(:professional) { create(:professional) }
  let(:patient) { create(:patient, professional: professional) }
  let(:granting_user) { patient.user }

  let(:other_pro_user) { create(:user) }
  let!(:other_pro) { create(:professional, user: other_pro_user) }

  subject(:run) do
    described_class.run(
      patient: patient,
      granting_user: granting_user,
      professional_email: email
    )
  end

  context "with a valid new professional email" do
    let(:email) { other_pro_user.email }

    it "creates a PatientProfessionalAccess record" do
      expect { run }.to change(PatientProfessionalAccess, :count).by(1)
    end

    it "returns the access record" do
      result = run
      expect(result.result).to be_a(PatientProfessionalAccess)
      expect(result.result.professional).to eq(other_pro)
      expect(result.result.patient).to eq(patient)
      expect(result.result.granted_by_patient_user).to eq(granting_user)
    end

    it "is valid" do
      expect(run).to be_valid
    end
  end

  context "when email does not match any professional" do
    let(:email) { "nobody@example.com" }

    it "does not create an access record" do
      expect { run }.not_to change(PatientProfessionalAccess, :count)
    end

    it "adds an error" do
      result = run
      expect(result.errors[:professional_email]).to include(
        I18n.t("patient.professional_accesses.errors.professional_not_found")
      )
    end
  end

  context "when email belongs to a user without a professional profile" do
    let(:plain_user) { create(:user) }
    let(:email) { plain_user.email }

    it "does not create an access record" do
      expect { run }.not_to change(PatientProfessionalAccess, :count)
    end

    it "adds a not found error" do
      result = run
      expect(result.errors[:professional_email]).to include(
        I18n.t("patient.professional_accesses.errors.professional_not_found")
      )
    end
  end

  context "when the professional is already the owner" do
    let(:email) { professional.user.email }

    it "does not create an access record" do
      expect { run }.not_to change(PatientProfessionalAccess, :count)
    end

    it "adds an already_owner error" do
      result = run
      expect(result.errors[:professional_email]).to include(
        I18n.t("patient.professional_accesses.errors.already_owner")
      )
    end
  end

  context "when the professional already has shared access" do
    let(:email) { other_pro_user.email }

    before do
      create(:patient_professional_access, patient: patient, professional: other_pro, granted_by_patient_user: granting_user)
    end

    it "does not create a duplicate access record" do
      expect { run }.not_to change(PatientProfessionalAccess, :count)
    end

    it "adds an already_shared error" do
      result = run
      expect(result.errors[:professional_email]).to include(
        I18n.t("patient.professional_accesses.errors.already_shared")
      )
    end
  end
end
