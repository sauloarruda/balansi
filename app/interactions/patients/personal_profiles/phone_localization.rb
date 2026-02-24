module Patients
  module PersonalProfiles
    module PhoneLocalization
      DEFAULT_COUNTRY = "BR".freeze
      COUNTRY_CODE_FORMAT = /\A[A-Z]{2}\z/

      module_function

      def default_country
        DEFAULT_COUNTRY
      end

      def normalize_country(raw_country)
        country_code = raw_country.to_s.upcase
        return default_country if country_code.blank?
        return country_code if country_code.match?(COUNTRY_CODE_FORMAT)

        default_country
      end

      def local_input_from_e164(phone_e164)
        parsed_phone = Phonelib.parse(phone_e164)
        if parsed_phone.valid?
          {
            country: normalize_country(parsed_phone.country),
            national_number: parsed_phone.national
          }
        else
          {
            country: default_country,
            national_number: nil
          }
        end
      end

      def parse_local_input(phone_national_number, phone_country)
        return nil if phone_national_number.blank?

        Phonelib.parse(phone_national_number.to_s, normalize_country(phone_country))
      end
    end
  end
end
