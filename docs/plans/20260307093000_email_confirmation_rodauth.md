# Email Confirmation via Rodauth

**Date:** 2026-03-07
**Branch:** `BAL-17-email-confirmation-rodauth`
**Status:** Ready for implementation

---

## Overview

Add Rodauth's built-in `verify_account` feature to require new users to confirm their email address before accessing the app. Existing users are unaffected. Unconfirmed users who attempt to log in are blocked and shown a resend option.

## Acceptance Criteria

- [ ] After sign-up, a confirmation email is sent via AWS SES
- [ ] New users are blocked from protected routes until email is confirmed
- [ ] Unconfirmed users attempting login see a clear error with a "Resend confirmation" link
- [ ] Clicking the confirmation link verifies the account and redirects to the app
- [ ] Existing users are not locked out (pre-set as verified in migration)
- [ ] Email views match app Slim/Tailwind style; email has inline CSS
- [ ] Both `pt` and `en` locales covered
- [ ] All new code covered by RSpec tests

---

## Implementation Steps

### Step 1: Database Migration

Create migration:

```ruby
# db/migrate/YYYYMMDDHHMMSS_add_verify_account_to_users.rb
class AddVerifyAccountToUsers < ActiveRecord::Migration[8.1]
  def change
    # Rodauth lifecycle status: 1=unverified, 2=open/verified, 3=closed.
    # Shared across verify_account and close_account features.
    # Use User#verified? for readable checks in application code.
    # Default is 2 so all existing users remain active after migration.
    add_column :users, :status_id, :integer, null: false, default: 2

    create_table :account_verification_keys, id: false do |t|
      t.integer  :id, null: false, primary_key: true
      t.string   :key, null: false
      t.datetime :requested_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :email_last_sent, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    add_foreign_key :account_verification_keys, :users, column: :id
  end
end
```

**Important:** `default: 2` keeps all existing users verified. For new signups, Rodauth sets `status_id = 1` on insert, then updates to `2` when the user clicks the confirmation link.

### Step 2: User Model — `verified?` Wrapper

Add to `app/models/user.rb`:

```ruby
# Rodauth status_id: 1=unverified, 2=open/verified, 3=closed
UNVERIFIED_STATUS = 1
OPEN_STATUS       = 2
CLOSED_STATUS     = 3

def verified?
  status_id == OPEN_STATUS
end
```

### Step 3: Enable Feature in Rodauth Config

In `app/misc/rodauth_main.rb`, update the `enable` list:

```ruby
enable :create_account, :login, :logout, :remember, :verify_account
```

Add configuration block after the existing login/account settings:

```ruby
# Verify account
verify_account_route "verify-email"
verify_account_resend_route "verify-email/resend"
verify_account_set_password? false
no_matching_verify_account_key_message { I18n.t("auth.rodauth.errors.invalid_verification_key") }
verify_account_notice_flash { I18n.t("auth.rodauth.flash.verify_account_success") }
resend_verify_account_notice_flash { I18n.t("auth.rodauth.flash.resend_verify_account_success") }
verify_account_email_sent_notice_flash { I18n.t("auth.rodauth.flash.verify_account_email_sent") }
unverified_account_message { I18n.t("auth.rodauth.errors.unverified_account") }
verify_account_email_subject { I18n.t("auth.rodauth.emails.verify_account.subject") }
```

### Step 4: Rodauth Views (Slim)

**`app/views/rodauth/verify_account.html.slim`** — "Check your email" page shown after signup:

```slim
- content_for :title, t("auth.local.verify_account.title")

h1.text-3xl.font-bold.mb-2 = t("auth.local.verify_account.title")
p.text-gray-600.mb-6 = t("auth.local.verify_account.description", email: rodauth.account[:email])

.mb-6.rounded-lg.border.border-blue-200.bg-blue-50.p-4.text-blue-800
  p = t("auth.local.verify_account.check_spam")

.pt-4
  p.text-sm.text-gray-600
    = t("auth.local.verify_account.no_email")
    |
    = link_to t("auth.local.verify_account.resend_link"), rodauth.verify_account_resend_path,
        class: "font-medium text-pink-700 hover:text-pink-800 hover:underline"
```

**`app/views/rodauth/verify_account_resend.html.slim`** — resend confirmation form:

```slim
- content_for :title, t("auth.local.verify_account_resend.title")

h1.text-3xl.font-bold.mb-2 = t("auth.local.verify_account_resend.title")
p.text-gray-600.mb-6 = t("auth.local.verify_account_resend.description")

= form_with url: rodauth.verify_account_resend_path, method: :post, data: { turbo: false }, class: "space-y-6" do |f|
  div
    = f.label rodauth.login_param, t("auth.local.fields.email")
    = f.email_field rodauth.login_param, id: rodauth.login_param, autocomplete: "email",
        required: true, placeholder: t("auth.local.fields.email_placeholder")

  .pt-4.border-t.border-gray-200
    = f.submit t("auth.local.verify_account_resend.submit"), tone: :pink, size: :sm, class: "w-full sm:w-auto"
```

**`app/views/rodauth/verify_account_email.text.slim`** — plain-text email:

```slim
= t("auth.rodauth.emails.verify_account.greeting", name: rodauth.account[:name])

= t("auth.rodauth.emails.verify_account.body")

= rodauth.verify_account_email_link

= t("auth.rodauth.emails.verify_account.ignore_hint")
```

**`app/views/rodauth/verify_account_email.html.slim`** — HTML email with inline CSS:

```slim
table width="100%" cellpadding="0" cellspacing="0" style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;"
  tr
    td style="padding-bottom: 24px;"
      h1 style="font-size: 24px; font-weight: bold; color: #111827; margin: 0;" Balansi

  tr
    td style="padding-bottom: 16px;"
      p style="font-size: 16px; color: #374151; margin: 0;"
        = t("auth.rodauth.emails.verify_account.greeting", name: rodauth.account[:name])

  tr
    td style="padding-bottom: 24px;"
      p style="font-size: 16px; color: #374151; margin: 0;"
        = t("auth.rodauth.emails.verify_account.body")

  tr
    td style="padding-bottom: 32px; text-align: center;"
      a href=rodauth.verify_account_email_link style="display: inline-block; background-color: #be185d; color: #ffffff; font-size: 16px; font-weight: 600; padding: 14px 28px; border-radius: 8px; text-decoration: none;"
        = t("auth.rodauth.emails.verify_account.cta")

  tr
    td style="padding-bottom: 16px; border-top: 1px solid #e5e7eb; padding-top: 16px;"
      p style="font-size: 12px; color: #6b7280; margin: 0;"
        = t("auth.rodauth.emails.verify_account.link_fallback")
      p style="font-size: 12px; color: #6b7280; word-break: break-all; margin: 4px 0 0 0;"
        = rodauth.verify_account_email_link

  tr
    td
      p style="font-size: 12px; color: #9ca3af; margin: 0;"
        = t("auth.rodauth.emails.verify_account.ignore_hint")
```

### Step 5: I18n Translations

**Add to `config/locales/pt.yml`** under `pt: auth:`:

```yaml
rodauth:
  flash:
    verify_account_success: "Email confirmado com sucesso. Bem-vindo!"
    resend_verify_account_success: "Email de confirmação reenviado."
    verify_account_email_sent: "Email de confirmação enviado. Verifique sua caixa de entrada."
  errors:
    unverified_account: "Você precisa confirmar seu email antes de fazer login. Verifique sua caixa de entrada ou reenvie o email."
    invalid_verification_key: "Link de verificação inválido ou expirado."
  emails:
    verify_account:
      subject: "Confirme seu email no Balansi"
      greeting: "Olá, %{name}!"
      body: "Clique no botão abaixo para confirmar seu endereço de email e ativar sua conta."
      cta: "Confirmar email"
      link_fallback: "Se o botão não funcionar, copie e cole este link no navegador:"
      ignore_hint: "Se você não criou uma conta no Balansi, ignore este email."
local:
  verify_account:
    title: "Verifique seu email"
    description: "Enviamos um link de confirmação para %{email}. Clique no link para ativar sua conta."
    check_spam: "Não encontrou o email? Verifique a pasta de spam ou lixo eletrônico."
    no_email: "Não recebeu o email?"
    resend_link: "Reenviar confirmação"
  verify_account_resend:
    title: "Reenviar confirmação"
    description: "Informe seu email para receber um novo link de confirmação."
    submit: "Reenviar email"
```

**Add equivalent keys to `config/locales/en.yml`:**

```yaml
rodauth:
  flash:
    verify_account_success: "Email confirmed successfully. Welcome!"
    resend_verify_account_success: "Confirmation email resent."
    verify_account_email_sent: "Confirmation email sent. Check your inbox."
  errors:
    unverified_account: "You need to confirm your email before signing in. Check your inbox or resend the confirmation email."
    invalid_verification_key: "Invalid or expired verification link."
  emails:
    verify_account:
      subject: "Confirm your email at Balansi"
      greeting: "Hello, %{name}!"
      body: "Click the button below to confirm your email address and activate your account."
      cta: "Confirm email"
      link_fallback: "If the button doesn't work, copy and paste this link into your browser:"
      ignore_hint: "If you didn't create a Balansi account, you can safely ignore this email."
local:
  verify_account:
    title: "Verify your email"
    description: "We sent a confirmation link to %{email}. Click it to activate your account."
    check_spam: "Can't find it? Check your spam or junk folder."
    no_email: "Didn't receive the email?"
    resend_link: "Resend confirmation"
  verify_account_resend:
    title: "Resend confirmation"
    description: "Enter your email to receive a new confirmation link."
    submit: "Resend email"
```

### Step 6: RSpec Tests

**`spec/system/auth/email_confirmation_spec.rb`** — system tests:
- New user sign-up triggers confirmation email (use `ActionMailer::Base.deliveries`)
- Unconfirmed user cannot log in — sees unverified_account message
- Clicking verification link confirms account and redirects to root
- Resend form sends another email

**`spec/mailers/rodauth_mailer_spec.rb`** (if Rodauth uses a separate mailer class, validate email subject/body).

---

## Files Changed

| File | Action |
|------|--------|
| `db/migrate/YYYYMMDDHHMMSS_add_verify_account_to_users.rb` | Create |
| `app/models/user.rb` | Edit — add `verified?` + status constants |
| `app/misc/rodauth_main.rb` | Edit — add `:verify_account`, config block |
| `app/views/rodauth/verify_account.html.slim` | Create |
| `app/views/rodauth/verify_account_resend.html.slim` | Create |
| `app/views/rodauth/verify_account_email.text.slim` | Create |
| `app/views/rodauth/verify_account_email.html.slim` | Create |
| `config/locales/pt.yml` | Edit — add verify_account keys |
| `config/locales/en.yml` | Edit — add verify_account keys |
| `spec/system/auth/email_confirmation_spec.rb` | Create |

---

## Key Constraints & Risks

| Risk | Mitigation |
|------|-----------|
| Existing users locked out | Migration defaults `status_id = 2` for all existing rows |
| SMTP not configured in dev | `perform_deliveries` only enabled when credentials present; use `letter_opener` or log in dev |
| Sequel + ActiveRecord dual stack | Rodauth uses Sequel internally — migration uses ActiveRecord, which is correct |
| `account[:name]` in email | Set in `before_create_account`; available via `rodauth.account[:name]` in email view |
| Token expiry UX | Rodauth's default token doesn't expire; add `verify_account_key_expiry` if needed later |

---

## Dev Testing Notes

In development with no SMTP credentials, emails are silently skipped (`perform_deliveries = false`). To test:
- Add test SMTP credentials to `config/credentials/development.yml.enc`, or
- Use `letter_opener` gem temporarily in dev, or
- Check `ActionMailer::Base.deliveries` in RSpec tests (test environment sets `delivery_method :test`)
