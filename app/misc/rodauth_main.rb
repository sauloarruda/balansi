require "sequel/core"

class RodauthMain < Rodauth::Rails::Auth
  configure do # rubocop:disable Metrics/BlockLength
    enable :create_account, :login, :logout, :remember

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
    login_param "email"
    login_confirm_param "email_confirmation"
    login_label { I18n.t("auth.local.fields.email") }
    password_label { I18n.t("auth.local.fields.password") }
    login_return_to_requested_location? true
    password_minimum_length 8
    password_maximum_bytes 72
    create_account_notice_flash { I18n.t("auth.rodauth.flash.create_account_success") }
    login_notice_flash { I18n.t("auth.rodauth.flash.login_success") }
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

    after_login { remember_login }
    extend_remember_deadline? true
    login_redirect { rails_routes.root_path }
    logout_redirect { rails_routes.auth_login_path }

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
      db.rollback_on_exit
      throw_error_status(
        422,
        "professional_id",
        I18n.t("auth.rodauth.errors.patient_profile_creation_failed", message: e.message)
      )
    end
  end

  private

  def validate_signup_context!
    throw_error_status(422, "name", I18n.t("auth.rodauth.errors.name_blank")) if normalized_name.blank?
    throw_error_status(422, "timezone", I18n.t("auth.rodauth.errors.invalid_timezone")) if normalized_timezone.blank?
    throw_error_status(422, "language", I18n.t("auth.rodauth.errors.invalid_language")) if normalized_language.blank?
    return if resolved_signup_professional.present?

    throw_error_status(422, "professional_id", signup_professional_error_message)
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
      professional_id = normalized_professional_id
      professional_id.present? ? Professional.find_by(id: professional_id) : Professional.order(:id).first
    end
  end

  def signup_professional_error_message
    if normalized_professional_id.present?
      I18n.t("auth.sign_up.errors.invalid_professional_signup_context")
    else
      I18n.t("auth.sign_up.errors.no_professionals_available_for_patient_assignment")
    end
  end

  def normalized_professional_id
    professional_id = param_or_nil("professional_id")
    return if professional_id.blank?

    value = Integer(professional_id, 10)
    value.positive? ? value : nil
  rescue ArgumentError, TypeError
    nil
  end
end
