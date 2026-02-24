require "rails_helper"

RSpec.describe Patients::PersonalProfiles::UpdateInteraction, type: :interaction do
  include ActiveSupport::Testing::TimeHelpers

  let(:patient) { create(:patient, :incomplete_profile) }

  around do |example|
    I18n.with_locale(:pt) { example.run }
  end

  def profile_params(attributes)
    ActionController::Parameters.new(attributes)
  end

  describe ".run" do
    it "updates patient profile and sets completion timestamps" do
      travel_to(Time.zone.local(2026, 2, 7, 9, 30, 0)) do
        result = described_class.run(
          patient: patient,
          profile_params: profile_params(
            gender: "male",
            birth_date: "10/03/1991",
            weight_kg: "78.5",
            height_cm: "182.0",
            phone_country: "BR",
            phone_national_number: "(11) 98888-7777"
          )
        )

        expect(result).to be_valid
      end

      patient.reload
      expect(patient.gender).to eq("male")
      expect(patient.birth_date).to eq(Date.new(1991, 3, 10))
      expect(patient.weight_kg).to eq(78.5)
      expect(patient.height_cm).to eq(182.0)
      expect(patient.phone_e164).to eq("+5511988887777")
      expect(patient.profile_completed_at).to eq(Time.zone.local(2026, 2, 7, 9, 30, 0))
      expect(patient.profile_last_updated_at).to eq(Time.zone.local(2026, 2, 7, 9, 30, 0))
    end

    it "fails when birth date is invalid for locale format" do
      result = described_class.run(
        patient: patient,
        profile_params: profile_params(
          gender: "male",
          birth_date: "31/31/1991",
          weight_kg: "78.5",
          height_cm: "182.0",
          phone_country: "BR",
          phone_national_number: "(11) 98888-7777"
        )
      )

      expect(result).not_to be_valid
      expect(result.errors[:birth_date]).to include(I18n.t("patient_personal_profile.messages.birth_date_invalid"))
      expect(patient.birth_date).to be_nil
    end

    it "fails when phone does not match selected country" do
      result = described_class.run(
        patient: patient,
        profile_params: profile_params(
          gender: "male",
          birth_date: "10/03/1991",
          weight_kg: "78.5",
          height_cm: "182.0",
          phone_country: "US",
          phone_national_number: "(11) 98888-7777"
        )
      )

      expect(result).not_to be_valid
      expect(result.errors[:phone_national_number]).to include(I18n.t("patient_personal_profile.messages.phone_invalid"))
      expect(patient.phone_e164).to eq("invalid")
    end

    it "fails gracefully when weight and height exceed decimal column range" do
      result = described_class.run(
        patient: patient,
        profile_params: profile_params(
          gender: "male",
          birth_date: "10/03/1991",
          weight_kg: "1000",
          height_cm: "1000",
          phone_country: "BR",
          phone_national_number: "(11) 98888-7777"
        )
      )

      expect(result).not_to be_valid
      expect(result.errors[:weight_kg]).to be_present
      expect(result.errors[:height_cm]).to be_present
    end
  end
end
