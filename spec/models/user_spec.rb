require "rails_helper"

RSpec.describe User, type: :model do
  describe "validations" do
    it "is valid with all required attributes" do
      user = build(:user)
      expect(user).to be_valid
    end

    it "requires timezone when explicitly set to nil" do
      user = build(:user, timezone: nil)
      expect(user).not_to be_valid
      expect(user.errors[:timezone]).to be_present
    end

    it "requires language when explicitly set to nil" do
      user = build(:user, language: nil)
      expect(user).not_to be_valid
      expect(user.errors[:language]).to be_present
    end

    it "validates timezone using IANA format" do
      user = build(:user, timezone: "America/Sao_Paulo")
      expect(user).to be_valid
    end

    it "rejects invalid IANA timezone and adds specific error message" do
      user = build(:user, timezone: "Invalid/Timezone")
      expect(user).not_to be_valid
      expect(user.errors[:timezone]).to include("is not a valid IANA timezone identifier (e.g., 'America/Sao_Paulo')")
    end

    it "validates language from available locales" do
      user = build(:user, language: "pt")
      expect(user).to be_valid
    end

    it "rejects invalid language" do
      user = build(:user, language: "invalid_lang")
      expect(user).not_to be_valid
      expect(user.errors[:language]).to be_present
    end
  end

  describe "associations" do
    it "has one patient" do
      user = create(:user)
      patient = create(:patient, user: user)

      expect(user.patient).to eq(patient)
    end

    it "has one professional" do
      user = create(:user)
      professional = create(:professional, user: user)

      expect(user.professional).to eq(professional)
    end

    it "destroys associated patient on destroy" do
      user = create(:user)
      patient = create(:patient, user: user)
      patient_id = patient.id

      user.destroy

      expect(Patient.exists?(patient_id)).to be false
    end
  end

  describe "database constraints" do
    it "has unique email constraint" do
      create(:user, email: "test@example.com", cognito_id: "cognito_123")

      duplicate_user = build(:user, email: "test@example.com", cognito_id: "cognito_456")
      expect {
        duplicate_user.save(validate: false)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "has unique cognito_id constraint" do
      create(:user, cognito_id: "cognito_123")

      duplicate_user = build(:user, cognito_id: "cognito_123")
      expect {
        duplicate_user.save(validate: false)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
