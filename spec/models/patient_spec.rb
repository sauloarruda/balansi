require "rails_helper"

# Factory Usage Pattern:
# - Use `create` for association and validation tests (requires DB persistence)
RSpec.describe Patient, type: :model do
  describe "validations" do
    it "is valid with user and professional_id" do
      patient = build(:patient)
      expect(patient).to be_valid
    end

    it "requires user" do
      patient = build(:patient, user: nil)
      expect(patient).not_to be_valid
      expect(patient.errors[:user]).to be_present
    end

    it "has professional_id" do
      patient = create(:patient, professional_id: 1)
      expect(patient.professional_id).to eq(1)
    end

    it "validates uniqueness of user_id and professional_id combination" do
      user = create(:user)
      create(:patient, user: user, professional_id: 1)

      duplicate_patient = build(:patient, user: user, professional_id: 1)
      expect(duplicate_patient).not_to be_valid
      expect(duplicate_patient.errors[:user_id].join(" ")).to include("already has a patient record for this professional")
    end
  end

  describe "associations" do
    it "belongs to user" do
      user = create(:user)
      patient = create(:patient, user: user)
      expect(patient.user.id).to eq(user.id)
    end
  end

  describe "scopes and uniqueness" do
    it "allows same professional_id for different users" do
      user1 = create(:user)
      user2 = create(:user)

      patient1 = create(:patient, user: user1, professional_id: 1)
      patient2 = create(:patient, user: user2, professional_id: 1)

      expect(patient1).to be_valid
      expect(patient2).to be_valid
      expect(patient1.professional_id).to eq(1)
      expect(patient2.professional_id).to eq(1)
    end

    it "allows different professional_ids for same user" do
      user = create(:user)

      patient1 = create(:patient, user: user, professional_id: 1)
      patient2 = create(:patient, user: user, professional_id: 2)

      expect(patient1).to be_valid
      expect(patient2).to be_valid
      expect(patient1.professional_id).to eq(1)
      expect(patient2.professional_id).to eq(2)
    end
  end
end
