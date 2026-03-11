# Professional Invite Code

**Date:** 2026-03-10
**Branch:** `BAL-XX-professional-invite-code`
**Status:** Ready for implementation

---

## Overview

Each professional receives a unique 6-character alphanumeric invite code stored on the `professionals` table. A patient signs up by visiting `/{invite_code}` at the root level, which redirects to the Rodauth signup page with the code in the query string. The signup flow validates the code and, on success, links the new patient to that professional as owner.

The existing `professional_id` param-based signup is replaced entirely by the invite code mechanism.

---

## Acceptance Criteria

- [ ] Every professional has a unique 6-character invite code generated on create
- [ ] Visiting `/{valid_code}` redirects to `/auth/sign_up?invite_code={code}`
- [ ] Visiting `/{unknown_code}` redirects to `/auth/sign_in`
- [ ] Accessing `/auth/sign_up` without a valid `invite_code` param redirects to `/auth/sign_in`
- [ ] Submitting the signup form with a valid `invite_code` creates the patient linked to that professional
- [ ] Submitting without or with an invalid `invite_code` returns a 422 with a clear error
- [ ] The professional context banner on the signup form shows when `invite_code` is present
- [ ] Both `pt` and `en` locales covered for the new error key
- [ ] All new code covered by RSpec (model, request)
- [ ] Existing tests updated to use `invite_code` instead of `professional_id`

---

## Architecture Overview

```
GET /{invite_code}
      |
      v
InvitesController#show
      |-- Professional.find_by(invite_code:) nil? --> redirect /auth/sign_in
      |-- found --> redirect /auth/sign_up?invite_code={code}

GET /auth/sign_up?invite_code=ABCD12
      |
      v
Rodauth create_account route (before hook)
      |-- normalized_invite_code blank? --> redirect /auth/sign_in
      |-- valid code? --> render signup form (invite_code hidden field)

POST /auth/sign_up (invite_code in params)
      |
      v
before_create_account
      |-- validate_signup_context! (uses resolved_signup_professional via invite_code)
      |-- sets name/timezone/language on account

after_create_account
      |-- Patient.find_or_create_by!(user_id:) { professional_id = resolved }
```

---

## Implementation Steps

### Step 1: Database Migration

- [ ] Generate migration: `bin/rails g migration AddInviteCodeToProfessionals`
- [ ] Write migration body (see snippet below)
- [ ] Run `bin/rails db:migrate`

```ruby
# db/migrate/YYYYMMDDHHMMSS_add_invite_code_to_professionals.rb
class AddInviteCodeToProfessionals < ActiveRecord::Migration[8.1]
  def up
    add_column :professionals, :invite_code, :string, limit: 6
    backfill_invite_codes
    change_column_null :professionals, :invite_code, false
    add_index :professionals, :invite_code, unique: true
  end

  def down
    remove_index :professionals, :invite_code if index_exists?(:professionals, :invite_code)
    remove_column :professionals, :invite_code
  end

  private

  def backfill_invite_codes
    Professional.find_each do |professional|
      loop do
        code = SecureRandom.alphanumeric(6).upcase
        unless Professional.exists?(invite_code: code)
          professional.update_columns(invite_code: code)
          break
        end
      end
    end
  end
end
```

Notes:
- `SecureRandom.alphanumeric(6).upcase` produces 6-character codes from `[A-Z0-9]`, giving 36^6 (~2.2 billion) combinations — far more than needed.
- The backfill loop with collision check is safe at any realistic scale.
- `change_column_null false` is applied after backfill so existing rows never violate the constraint.
- The unique index is added last to avoid backfill conflicts on the DB level (SQLite will not enforce partial uniqueness mid-loop anyway, but this is the intent).

---

### Step 2: Professional Model

- [ ] Add `before_create :generate_invite_code`
- [ ] Add `validates :invite_code, presence: true, uniqueness: true, length: { is: 6 }`

```ruby
# app/models/professional.rb
class Professional < ApplicationRecord
  belongs_to :user

  has_many :owned_patients, class_name: "Patient", dependent: :restrict_with_error
  has_many :patient_professional_accesses, dependent: :destroy
  has_many :shared_patients, through: :patient_professional_accesses, source: :patient

  validates :user_id, uniqueness: true
  validates :invite_code, presence: true, uniqueness: true, length: { is: 6 },
                          format: { with: /\A[A-Z0-9]{6}\z/ }

  before_create :generate_invite_code

  def linked_patients
    base = Patient.includes(:user)
    base.where(professional_id: id).or(
      base.where(id: patient_professional_accesses.select(:patient_id))
    )
  end

  def owner_of?(patient)
    patient.professional_id == id
  end

  def can_access?(patient)
    owner_of?(patient) || shared_patients.exists?(id: patient.id)
  end

  private

  def generate_invite_code
    loop do
      self.invite_code = SecureRandom.alphanumeric(6).upcase
      break unless Professional.exists?(invite_code: invite_code)
    end
  end
end
```

Notes on collision safety: The loop retries generation if a duplicate is found. At realistic professional counts (hundreds to low thousands) the chance of collision on any given call is negligible. The DB unique index serves as the final safety net — if an extremely rare race condition occurs on create, the DB will raise `ActiveRecord::RecordNotUnique`; the caller (typically a one-time admin action) can simply retry.

---

### Step 3: InvitesController

- [ ] Create `app/controllers/invites_controller.rb`
- [ ] Skip authentication for this controller (it is a public entry point)

```ruby
# app/controllers/invites_controller.rb
class InvitesController < ActionController::Base
  include BrowserLanguage
  include BrowserTimezone

  def show
    professional = Professional.find_by(invite_code: params[:invite_code].to_s.upcase)

    if professional
      redirect_to "#{rodauth_sign_up_path}?invite_code=#{professional.invite_code}"
    else
      redirect_to "/auth/sign_in"
    end
  end

  private

  def rodauth_sign_up_path
    "/auth/sign_up"
  end
end
```

Key decision — inherit from `ActionController::Base`, not `ApplicationController`:

`ApplicationController` includes the `Authentication` concern, which adds `before_action :authenticate_user!`. That would block unauthenticated visitors before `show` can even run. Inheriting directly from `ActionController::Base` keeps the controller lean and avoids the need for `skip_before_action` chains against all the other before-actions defined in `ApplicationController` (`ensure_current_patient!`, `ensure_patient_personal_profile_completed!`, etc.).

The `BrowserLanguage` and `BrowserTimezone` concerns are included only if the controller needs locale/timezone detection (e.g., if you add a rendered error page in the future). They are optional and can be omitted for now.

Simpler alternative (fully equivalent for this step):

```ruby
# Note: inherits from ActionController::Base (not ApplicationController) intentionally.
# ApplicationController adds authenticate_user! and other before-actions that would block
# unauthenticated visitors. This controller only redirects, so CSRF protection is not needed.
class InvitesController < ActionController::Base
  def show
    professional = Professional.find_by(invite_code: params[:invite_code].to_s.upcase)
    redirect_to professional ? "/auth/sign_up?invite_code=#{professional.invite_code}" : "/auth/sign_in"
  end
end
```

---

### Step 4: Routes

- [ ] Add the `/:invite_code` route at the bottom of `routes.rb`, just before `root`
- [ ] The route must be placed LAST among `get` routes to avoid shadowing existing named paths

```ruby
# config/routes.rb (additions only — place just before the root declaration)

  # Public invite entry point — must be declared LAST to avoid shadowing other routes
  get "/:invite_code", to: "invites#show", as: :invite_signup,
      constraints: { invite_code: /[A-Za-z0-9]{6}/ }

  root to: redirect { |params, request| "/journals/today#{request.query_string.present? ? "?#{request.query_string}" : ""}" }
```

The regex constraint `[A-Za-z0-9]{6}` is important for two reasons:

1. It prevents the wildcard from swallowing existing static routes that happen to match (e.g., if a future route is added above without the constraint being respected, this adds a guard at the router level).
2. It ensures that paths like `/up`, `/403`, `/404`, `/500` — which are all defined before this route — are never matched here (those are defined first so Rails will resolve them before reaching `/:invite_code`).

The error pages `/403`, `/404`, `/500` use `match via: :all` and are declared at the top. `get "up"` and the `/auth/*` mount are also declared before the invite route, so there is no shadowing concern with the ordering as long as this route stays last.

---

### Step 5: Rodauth Changes

This is the most critical section. Three private methods change and one new hook is added.

- [ ] Add `before_create_account_route` hook for GET guard
- [ ] Replace `resolved_signup_professional` (invite code lookup, no fallback)
- [ ] Replace `normalized_professional_id` with `normalized_invite_code`
- [ ] Update `validate_signup_context!` error field name from `"professional_id"` to `"invite_code"`
- [ ] Update `after_create_account` error field name from `"professional_id"` to `"invite_code"`
- [ ] Remove `signup_professional_error_message` helper or update it

Full diff for `app/misc/rodauth_main.rb`:

```ruby
# Inside configure do ... end block

# ADD: Guard the signup GET route — redirect to login if no valid invite code
before_create_account_route do
  if request.get? && normalized_invite_code.blank?
    redirect rails_routes.auth_login_path
  end
end

# KEEP (unchanged):
before_create_account do
  validate_signup_context!

  now = Time.current
  account[:name] = normalized_name
  account[:timezone] = normalized_timezone
  account[:language] = normalized_language
  account[:created_at] = now
  account[:updated_at] = now
end

# CHANGE: field name in rescue block from "professional_id" to "invite_code"
after_create_account do
  Patient.find_or_create_by!(user_id: account_id) do |patient|
    patient.professional_id = resolved_signup_professional.id
  end
rescue ActiveRecord::ActiveRecordError => e
  db.rollback_on_exit
  throw_error_status(
    422,
    "invite_code",
    I18n.t("auth.rodauth.errors.patient_profile_creation_failed", message: e.message)
  )
end
```

```ruby
# Private methods section

# CHANGE: error field from "professional_id" to "invite_code"
def validate_signup_context!
  throw_error_status(422, "name", I18n.t("auth.rodauth.errors.name_blank")) if normalized_name.blank?
  throw_error_status(422, "timezone", I18n.t("auth.rodauth.errors.invalid_timezone")) if normalized_timezone.blank?
  throw_error_status(422, "language", I18n.t("auth.rodauth.errors.invalid_language")) if normalized_language.blank?
  return if resolved_signup_professional.present?

  throw_error_status(422, "invite_code", I18n.t("auth.sign_up.errors.invalid_invite_code"))
end

# CHANGE: look up by invite_code, no fallback to first professional
def resolved_signup_professional
  @resolved_signup_professional ||= begin
    code = normalized_invite_code
    code.present? ? Professional.find_by(invite_code: code) : nil
  end
end

# ADD: replaces normalized_professional_id
def normalized_invite_code
  code = param_or_nil("invite_code")
  return if code.blank?

  sanitized = code.to_s.strip.upcase
  sanitized.match?(/\A[A-Z0-9]{6}\z/) ? sanitized : nil
end

# REMOVE: normalized_professional_id (no longer used)
# REMOVE: signup_professional_error_message (collapsed into validate_signup_context!)
```

Notes on `before_create_account_route`:

Rodauth exposes `before_#{route}_route` hooks that run before the route handler for that feature. The hook fires on both GET and POST to the sign-up path. The guard is scoped to `request.get?` so that a POST with a missing/invalid invite code still reaches `before_create_account` and returns a proper 422 form error (rather than silently redirecting). This gives the user a field-level error on the form, which is the correct UX for a form submission.

Notes on removing the fallback:

The old `resolved_signup_professional` fell back to `Professional.order(:id).first` when no `professional_id` was provided. This was a development convenience. The new implementation returns `nil` when no code is given, which triggers the redirect guard on GET and a 422 on POST. There is no silent fallback.

---

### Step 6: Signup View

- [ ] Replace `f.hidden_field "professional_id"` with `f.hidden_field "invite_code"`
- [ ] Update `general_errors` field list from `"professional_id"` to `"invite_code"`
- [ ] Update the professional context banner condition from `params[:professional_id]` to `params[:invite_code]`

```slim
/ app/views/rodauth/create_account.html.slim

- content_for :title, t("auth.local.create_account.title")

- name_error = rodauth.field_error("name")
- login_error = rodauth.field_error(rodauth.login_param)
- login_confirm_error = rodauth.field_error(rodauth.login_confirm_param)
- password_error = rodauth.field_error(rodauth.password_param)
- password_confirm_error = rodauth.field_error(rodauth.password_confirm_param)
- general_errors = %w[invite_code timezone language].filter_map { |field| rodauth.field_error(field) }.uniq
- form_has_errors = general_errors.any? || [name_error, login_error, login_confirm_error, password_error, password_confirm_error].any?(&:present?)

h1.text-3xl.font-bold.mb-2 = t("auth.local.create_account.title")
p.text-gray-600.mb-6 = t("auth.local.create_account.description")

- if params[:invite_code].present?
  .mb-6.rounded-lg.border.border-blue-200.bg-blue-50.p-4.text-blue-800
    = t("auth.local.create_account.professional_context")

= form_with url: rodauth.create_account_path, method: :post, data: { turbo: false }, class: "space-y-6" do |f|
  - if form_has_errors
    .mb-6.p-4.bg-red-50.border.border-red-200.text-red-800.rounded-lg role="alert" aria-live="assertive"
      p.text-sm.font-medium = t("forms.errors.alert")
      - if general_errors.any?
        ul.mt-2.list-disc.space-y-1.pl-5.text-sm
          - general_errors.each do |error|
            li = error

  = f.hidden_field "invite_code", value: params[:invite_code]

  / ... rest of form unchanged ...
```

---

### Step 7: I18n Updates

- [ ] Add `invalid_invite_code` under `auth.sign_up.errors` in both locale files
- [ ] Remove `invalid_professional_signup_context` and `no_professionals_available_for_patient_assignment` — these are no longer referenced and should be deleted, not left as dead keys

`config/locales/en.yml` — change under `auth.sign_up.errors`:

```yaml
auth:
  sign_up:
    errors:
      invalid_invite_code: "Invalid or expired invite code."
      # keep old keys during transition if needed, or remove:
      # invalid_professional_signup_context: ...
      # no_professionals_available_for_patient_assignment: ...
```

`config/locales/pt.yml` — change under `auth.sign_up.errors`:

```yaml
auth:
  sign_up:
    errors:
      invalid_invite_code: "Código de convite inválido ou expirado."
```

---

### Step 8: Update Existing Tests

Three spec files require updates. **Critical:** after the GET guard is in place, `authenticity_token_for(auth_sign_up_path)` (without invite_code) will return `nil` because the GET redirects to login instead of rendering the form. All calls to `authenticity_token_for` for the signup path **must** include `invite_code`.

#### 8a. `spec/requests/rodauth_authentication_spec.rb`

- [ ] Update `"creates a user and patient profile"` test — add `invite_code` to `authenticity_token_for` call and POST params
- [ ] Replace `"uses the provided professional_id when present"` test with `invite_code` equivalent
- [ ] Update `"shows a specific message when the email is already taken"` (line 83) — add `invite_code`
- [ ] Update `"shows validation errors in the browser language"` (line 102) — add `invite_code`

```ruby
# spec/requests/rodauth_authentication_spec.rb (relevant tests rewritten)

RSpec.describe "Rodauth authentication", type: :request do
  let!(:owner_professional) { create(:professional) }  # invite_code auto-generated

  # ...

  describe "POST /auth/sign_up" do
    it "creates a user and patient profile, then redirects to verify-email page" do
      token = authenticity_token_for(auth_sign_up_path(invite_code: owner_professional.invite_code))

      expect do
        post auth_sign_up_path, params: {
          authenticity_token: token,
          name: "Nova Pessoa",
          email: "nova@example.com",
          email_confirmation: "nova@example.com",
          password: "password123",
          "password-confirm" => "password123",
          invite_code: owner_professional.invite_code
        }, headers: { "Accept-Language" => "en-US" }
      end.to change(User, :count).by(1).and change(Patient, :count).by(1)

      user = User.order(:id).last

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to("/auth/verify-email/resend")
      expect(user.patient.professional_id).to eq(owner_professional.id)
    end

    it "links the patient to the professional identified by invite_code" do
      selected_professional = create(:professional)
      token = authenticity_token_for(auth_sign_up_path(invite_code: selected_professional.invite_code))

      post auth_sign_up_path, params: {
        authenticity_token: token,
        name: "Paciente Vinculado",
        email: "vinculado@example.com",
        email_confirmation: "vinculado@example.com",
        password: "password123",
        "password-confirm" => "password123",
        invite_code: selected_professional.invite_code
      }

      expect(response).to have_http_status(:found)
      expect(User.order(:id).last.patient.professional_id).to eq(selected_professional.id)
    end

    it "shows a specific message when the email is already taken" do
      existing_user = create(:user, email: "existing-signup@example.com")
      create(:patient, user: existing_user)
      token = authenticity_token_for(auth_sign_up_path(invite_code: owner_professional.invite_code))

      post auth_sign_up_path, params: {
        authenticity_token: token,
        name: "Pessoa Duplicada",
        email: existing_user.email,
        email_confirmation: existing_user.email,
        password: "password123",
        "password-confirm" => "password123",
        invite_code: owner_professional.invite_code
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Já existe uma conta com este email.")
    end

    it "shows validation errors in the browser language for unauthenticated requests" do
      existing_user = create(:user, email: "existing-english-signup@example.com")
      create(:patient, user: existing_user)
      token = authenticity_token_for(auth_sign_up_path(invite_code: owner_professional.invite_code))

      post auth_sign_up_path, params: {
        authenticity_token: token,
        name: "Existing Person",
        email: existing_user.email,
        email_confirmation: existing_user.email,
        password: "password123",
        "password-confirm" => "password123",
        invite_code: owner_professional.invite_code
      }, headers: { "Accept-Language" => "en-US,en;q=0.9" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("An account with this email already exists.")
    end

    it "redirects to sign_in when no invite_code is provided on GET" do
      get auth_sign_up_path
      expect(response).to redirect_to(auth_login_path)
    end

    it "returns 422 with error when posting without an invite_code" do
      token = authenticity_token_for(auth_sign_up_path(invite_code: owner_professional.invite_code))

      post auth_sign_up_path, params: {
        authenticity_token: token,
        name: "Sem Codigo",
        email: "semcodigo@example.com",
        email_confirmation: "semcodigo@example.com",
        password: "password123",
        "password-confirm" => "password123"
        # invite_code intentionally omitted
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Invalid or expired invite code")
        .or include("Código de convite inválido")
    end
  end
```

#### 8b. `spec/requests/rodauth_email_confirmation_spec.rb`

- [ ] Update `sign_up_as` helper to include `invite_code` (uses `owner_professional` already defined in outer `let!`)

```ruby
# spec/requests/rodauth_email_confirmation_spec.rb — update sign_up_as helper

def sign_up_as(email:, name: "Test Person")
  token = authenticity_token_for(auth_sign_up_path(invite_code: owner_professional.invite_code))
  post auth_sign_up_path, params: {
    authenticity_token: token,
    name: name,
    email: email,
    email_confirmation: email,
    password: "password123",
    "password-confirm" => "password123",
    invite_code: owner_professional.invite_code
  }
end
```

Note: `owner_professional` is already defined as `let!(:owner_professional) { create(:professional) }` at line 5 of that file — no change needed to the let.

---

### Step 9: New Tests

- [ ] `spec/models/professional_spec.rb` — invite code generation tests
- [ ] `spec/requests/invites_spec.rb` — InvitesController tests

```ruby
# spec/models/professional_spec.rb additions

describe "invite_code" do
  it "is auto-generated on create" do
    professional = create(:professional)
    expect(professional.invite_code).to match(/\A[A-Z0-9]{6}\z/)
  end

  it "is unique across professionals" do
    p1 = create(:professional)
    p2 = create(:professional)
    expect(p1.invite_code).not_to eq(p2.invite_code)
  end

  it "enforces uniqueness at the model level" do
    existing = create(:professional)
    duplicate = build(:professional, invite_code: existing.invite_code)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:invite_code]).to be_present
  end

  it "validates length of 6" do
    professional = build(:professional, invite_code: "ABC")
    expect(professional).not_to be_valid
  end
end
```

```ruby
# spec/requests/invites_spec.rb
require "rails_helper"

RSpec.describe "Invites", type: :request do
  describe "GET /:invite_code" do
    it "redirects to signup with the invite_code when the code is valid" do
      professional = create(:professional)

      get "/#{professional.invite_code}"

      expect(response).to redirect_to("/auth/sign_up?invite_code=#{professional.invite_code}")
    end

    it "redirects to sign_in when the invite_code is unknown" do
      get "/XXXXXX"

      expect(response).to redirect_to("/auth/sign_in")
    end

    it "is case-insensitive — upcases the code before lookup" do
      professional = create(:professional)
      lower_code = professional.invite_code.downcase

      get "/#{lower_code}"

      expect(response).to redirect_to("/auth/sign_up?invite_code=#{professional.invite_code}")
    end
  end
end
```

---

### Step 10: Factory Update

- [ ] The `:professional` factory requires no change — `before_create :generate_invite_code` handles code generation automatically
- [ ] If any factory explicitly sets `invite_code`, ensure it is a valid 6-char alphanumeric value

```ruby
# spec/factories/professionals.rb — no change needed
FactoryBot.define do
  factory :professional do
    association :user
    # invite_code is generated by the model callback
  end
end
```

---

## Edge Cases and Error Handling

### Route Collision Risk
The `/:invite_code` route with the `[A-Za-z0-9]{6}` constraint will not match `/up` (2 chars), `/403` (3 chars with a slash), or `/auth/sign_in` (path with a slash). The error pages are matched via `match via: :all` at the top of routes. The ordering in `routes.rb` ensures all other routes are evaluated first. No collision risk exists with the current route table.

### Invite Code Collision on Create
The `generate_invite_code` loop retries on collision. At 1,000 professionals the chance of any collision is ~1 in 2.2 million per attempt. The DB unique index is the authoritative safety net. An `ActiveRecord::RecordNotUnique` rescue could be added to the model's `create` if extremely strict retry behaviour is required, but it is not needed in practice.

### POST Without Invite Code (Direct API Access)
If someone POSTs to `/auth/sign_up` without an `invite_code` (bypassing the form), `normalized_invite_code` returns `nil`, `resolved_signup_professional` returns `nil`, and `validate_signup_context!` throws a 422 with the `"invite_code"` field error. This surfaces on the form as a general error.

### Before-Route Hook on POST
The `before_create_account_route` hook is gated to `request.get?`. On POST, the hook is a no-op; validation happens inside `before_create_account` via `validate_signup_context!`. This is intentional: a GET with no code should redirect silently; a POST with no code should return a form error so the user sees what went wrong.

### Existing Professionals Without Codes (migration backfill)
The migration backfills codes for all existing professionals before applying `NOT NULL`. The development shortcut `Professional.order(:id).first` fallback is removed, so any test or seed that creates a professional without an invite_code will now require the model callback (which fires on `create`). Factories are unaffected because FactoryBot calls `create` which triggers the callback.

### Case Handling
Invite codes are stored and generated as uppercase (`SecureRandom.alphanumeric(6).upcase`). The `InvitesController` upcases the incoming param before lookup (`params[:invite_code].to_s.upcase`). `normalized_invite_code` in Rodauth also upcases before lookup. This ensures lowercase URLs like `/abc123` resolve correctly.

---

## Migration Rollback Considerations

- Rolling back removes the `invite_code` column and its index
- Any existing code that references `invite_code` will fail after rollback
- The old `professional_id` param flow is removed in this feature; restoring it requires reverting `rodauth_main.rb`, the view, and the routes in addition to rolling back the migration

---

## Files to Create/Modify

| File | Action |
|------|--------|
| `db/migrate/YYYYMMDDHHMMSS_add_invite_code_to_professionals.rb` | CREATE |
| `app/models/professional.rb` | MODIFY |
| `app/controllers/invites_controller.rb` | CREATE |
| `config/routes.rb` | MODIFY |
| `app/misc/rodauth_main.rb` | MODIFY |
| `app/views/rodauth/create_account.html.slim` | MODIFY |
| `config/locales/en.yml` | MODIFY |
| `config/locales/pt.yml` | MODIFY |
| `spec/models/professional_spec.rb` | MODIFY |
| `spec/requests/rodauth_authentication_spec.rb` | MODIFY |
| `spec/requests/rodauth_email_confirmation_spec.rb` | MODIFY |
| `spec/requests/invites_spec.rb` | CREATE |
| `spec/factories/professionals.rb` | No change needed |

---

## Testing Strategy

Run the full suite after each step:

```bash
bundle exec rspec spec/models/professional_spec.rb
bundle exec rspec spec/requests/invites_spec.rb
bundle exec rspec spec/requests/rodauth_authentication_spec.rb
bundle exec rspec spec/requests/rodauth_email_confirmation_spec.rb
bundle exec rspec  # full suite
```

Linting:

```bash
bundle exec rubocop app/models/professional.rb app/controllers/invites_controller.rb app/misc/rodauth_main.rb config/routes.rb
```
