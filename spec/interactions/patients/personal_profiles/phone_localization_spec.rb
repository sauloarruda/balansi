require "rails_helper"

RSpec.describe Patients::PersonalProfiles::PhoneLocalization do
  describe ".normalize_country" do
    it "returns default country when blank" do
      expect(described_class.normalize_country(nil)).to eq("BR")
      expect(described_class.normalize_country("")).to eq("BR")
    end

    it "normalizes valid country code to uppercase" do
      expect(described_class.normalize_country("us")).to eq("US")
    end

    it "falls back to default country for invalid codes" do
      expect(described_class.normalize_country("USA")).to eq("BR")
      expect(described_class.normalize_country("1")).to eq("BR")
    end
  end

  describe ".local_input_from_e164" do
    it "returns country and national number when phone is valid" do
      result = described_class.local_input_from_e164("+5511988887777")
      expected_national_number = Phonelib.parse("+5511988887777").national

      expect(result).to eq(country: "BR", national_number: expected_national_number)
    end

    it "returns default country and nil number when phone is invalid" do
      result = described_class.local_input_from_e164("invalid")

      expect(result).to eq(country: "BR", national_number: nil)
    end
  end

  describe ".parse_local_input" do
    it "parses local number using normalized country code" do
      parsed_phone = described_class.parse_local_input("(415) 555-2671", "us")

      expect(parsed_phone).to be_valid
      expect(parsed_phone.full_e164).to eq("+14155552671")
    end

    it "returns nil when number is blank" do
      expect(described_class.parse_local_input("", "BR")).to be_nil
    end
  end
end
