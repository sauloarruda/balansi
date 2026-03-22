require "sequel/core"

class RodauthMain < Rodauth::Rails::Auth
  configure do # rubocop:disable Metrics/BlockLength
    enable :create_account, :login, :logout, :remember, :verify_account

    db Sequel.sqlite(extensions: :activerecord_connection, keep_reference: false)
    convert_token_id_to_integer? { User.columns_hash["id"].type == :integer }

    accounts_table :users
    remember_table :user_remember_keys
    rails_account_model { User }
    account_password_hash_column :password_hash
    session_key :user_id
    prefix "/auth"
    login_route "sign_in"
    create_account_route "sign_up"
    logout_route "sign_out"

    rails_controller { RodauthController }
    title_instance_variable :@page_title
    flash_error_key :alert
    email_from do
      Rails.application.credentials.mailer_from ||
        ENV.fetch("MAILER_FROM", "support@#{Rails.application.config.action_mailer.default_url_options&.fetch(:host, "localhost")}")
    end
    login_param "email"
    require_login_confirmation? { false }
    login_label { I18n.t("auth.local.fields.email") }
    password_label { I18n.t("auth.local.fields.password") }
    login_return_to_requested_location? true
    password_minimum_length 8
    password_maximum_bytes 72
    create_account_notice_flash { I18n.t("auth.rodauth.flash.create_account_success") }
    login_notice_flash { I18n.t("auth.rodauth.flash.login_success") }
    login_error_flash { I18n.t("auth.rodauth.flash.login_error") }
    logout_notice_flash { I18n.t("auth.rodauth.flash.logout_success") }
    require_login_error_flash { I18n.t("auth.rodauth.flash.login_required") }
    no_matching_login_message { I18n.t("auth.rodauth.errors.no_matching_login") }
    invalid_password_message { I18n.t("auth.rodauth.errors.invalid_password") }
    already_an_account_with_this_login_message { I18n.t("auth.rodauth.errors.login_taken") }
    password_too_short_message do
      I18n.t("auth.rodauth.errors.password_too_short", count: password_minimum_length)
    end
    login_not_valid_email_message { I18n.t("auth.rodauth.errors.invalid_email") }
    login_does_not_meet_requirements_message do
      login_requirement_message.presence || login_not_valid_email_message
    end

    # Verify account
    verify_account_route "verify-email"
    verify_account_resend_route "verify-email/resend"
    verify_account_set_password? { false }
    no_matching_verify_account_key_error_flash { I18n.t("auth.rodauth.errors.invalid_verification_key") }
    verify_account_notice_flash { I18n.t("auth.rodauth.flash.verify_account_success") }
    verify_account_email_sent_notice_flash { I18n.t("auth.rodauth.flash.verify_account_email_sent") }
    verify_account_email_recently_sent_error_flash { I18n.t("auth.rodauth.flash.verify_account_email_recently_sent") }
    attempt_to_login_to_unverified_account_error_flash { I18n.t("auth.rodauth.errors.unverified_account") }
    verify_account_email_subject { I18n.t("auth.rodauth.emails.verify_account.subject") }
    create_account_redirect { "#{prefix}/verify-email/resend" }
    verify_account_redirect { login_redirect }

    create_verify_account_email do
      RodauthMailer.verify_account(self.class.configuration_name, account_id, verify_account_key_value)
    end

    send_verify_account_email do
      create_verify_account_email.deliver_later
    end

    after_login { remember_login }
    extend_remember_deadline? true
    login_redirect { rails_routes.root_path }
    logout_redirect { rails_routes.auth_login_path }

    before_create_account_route do
      redirect rails_routes.auth_login_path if request.get? && invalid_signup_state?
      rails_controller_instance.instance_variable_set(:@signup_professional, resolved_signup_professional)
    end

    before_create_account do
      validate_signup_context!

      now = Time.current
      account[:name] = normalized_name
      account[:timezone] = normalized_timezone
      account[:language] = normalized_language
      account[:created_at] = now
      account[:updated_at] = now
    end

    after_create_account do
      Patient.find_or_create_by!(user_id: account_id) do |patient|
        patient.professional_id = resolved_signup_professional.id
      end
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.error(
        "Patient profile creation failed for account_id=#{account_id}: #{e.class}: #{e.message}"
      )
      db.rollback_on_exit
      throw_error_status(
        422,
        "invite_code",
        I18n.t("auth.rodauth.errors.patient_profile_creation_failed")
      )
    end
  end

  private

  def validate_signup_context!
    throw_error_status(422, "name", I18n.t("auth.rodauth.errors.name_blank")) if normalized_name.blank?
    throw_error_status(422, "timezone", I18n.t("auth.rodauth.errors.invalid_timezone")) if normalized_timezone.blank?
    throw_error_status(422, "language", I18n.t("auth.rodauth.errors.invalid_language")) if normalized_language.blank?
    return if resolved_signup_professional.present?

    throw_error_status(422, "invite_code", I18n.t("auth.sign_up.errors.invalid_invite_code"))
  end

  def normalized_name
    param_or_nil("name")&.strip
  end

  def normalized_timezone
    timezone = request.cookies["timezone"].presence || "America/Sao_Paulo"
    TZInfo::Timezone.get(timezone)
    timezone
  rescue TZInfo::InvalidTimezoneIdentifier
    nil
  end

  def normalized_language
    locale = rails_controller_instance&.send(:detect_browser_language).to_s
    locale.in?(%w[pt en]) ? locale : "pt"
  end

  def logged_in_via_remember_key?
    authenticated_by&.include?("remember") || false
  end

  def resolved_signup_professional
    @resolved_signup_professional ||= begin
      code = normalized_invite_code
      code.present? ? Professional.find_by(invite_code: code) : nil
    end
  end

  def invalid_signup_state?
    normalized_invite_code.blank? || resolved_signup_professional.nil?
  end

  def normalized_invite_code
    code = param_or_nil("invite_code")
    return if code.blank?

    sanitized = code.to_s.strip.upcase
    sanitized.match?(Professional::INVITE_CODE_FORMAT) ? sanitized : nil
  end
end
