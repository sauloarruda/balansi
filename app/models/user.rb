class User < ApplicationRecord
  # Associations
  has_many :patients, dependent: :destroy

  # Validations
  validates :timezone, presence: true
  validates :language, presence: true, inclusion: { in: -> { User.valid_languages } }

  validate :valid_iana_timezone

  # Validate timezone using IANA format (e.g., "America/Sao_Paulo")
  # This is the standard format returned by JavaScript Intl.DateTimeFormat
  def valid_iana_timezone
    return if timezone.blank?

    begin
      # Use TZInfo to validate IANA timezone identifier
      TZInfo::Timezone.get(timezone)
    rescue TZInfo::InvalidTimezoneIdentifier
      errors.add(:timezone, "is not a valid IANA timezone identifier (e.g., 'America/Sao_Paulo')")
    end
  end

  # Get list of valid languages from Rails i18n configuration
  def self.valid_languages
    Rails.application.config.i18n.available_locales.map(&:to_s)
  end
end
