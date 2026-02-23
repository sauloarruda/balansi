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
end
