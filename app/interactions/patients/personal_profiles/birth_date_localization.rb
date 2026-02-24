module Patients
  module PersonalProfiles
    module BirthDateLocalization
      module_function

      def parse(raw_birth_date)
        return nil if raw_birth_date.blank?
        return raw_birth_date if raw_birth_date.is_a?(Date)

        birth_date_string = raw_birth_date.to_s.strip
        return Date.iso8601(birth_date_string) if birth_date_string.match?(/\A\d{4}-\d{2}-\d{2}\z/)

        Date.strptime(birth_date_string, localized_format)
      rescue ArgumentError
        :invalid
      end

      def format(date)
        return nil if date.blank?

        date.strftime(localized_format)
      end

      def mask
        I18n.t("patient_personal_profile.show.birth_date_mask")
      end

      def localized_format
        I18n.t("patient_personal_profile.show.birth_date_format")
      end
    end
  end
end
