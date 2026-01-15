# Entity Relationship Diagram — Authentication (Balansi)

## 1. Architecture Overview

The Authentication module provides secure user registration and login for the Balansi platform using **AWS Cognito Hosted UI**. This simplified architecture eliminates the need for custom authentication forms and leverages Rails native session management.

**Key Components:**
- **Frontend**: Rails views (no custom auth pages - uses Cognito Hosted UI)
- **Backend**: Ruby on Rails application (handles callback and session management)
- **Identity Provider**: AWS Cognito Hosted UI (handles all login/signup/password recovery forms)
- **Database**: PostgreSQL (user records, patient records)
- **Session Storage**: Rails session with httpOnly cookies
- **Infrastructure**: All services hosted in Brazil (AWS sa-east-1 - São Paulo) for low latency
- **Localization**: Browser language detection (pt-BR or en), default pt-BR. Application supports pt-BR and en translations in v1
- **Timezone**: Browser timezone detection stored in user record, default 'America/Sao_Paulo'

**Key Design Decisions:**
- **Cognito Hosted UI**: All authentication forms (signup, login, password recovery) are handled entirely by Cognito
- **No Custom Auth Pages**: Rails redirects to Cognito Hosted UI instead of showing custom forms
- **Callback Endpoint**: Single endpoint (`/auth/callback`) handles post-authentication processing
- **Rails Session**: Uses Rails native session management with httpOnly cookies (no JWT tokens in frontend)
- **Auto-Create Records**: User and Patient records are created automatically during callback (onboarding to be implemented later)
- **Minimal Implementation**: Leverages 100% of Cognito features, implementing only the minimum necessary in Rails
- **Brazilian Hosting**: All infrastructure hosted in Brazil (sa-east-1) to minimize network latency for Brazilian users
- **Browser Language Detection**: Language detected from Accept-Language header (pt-BR or en), defaults to pt-BR if not detected or not supported
- **Multi-language Support**: Application supports pt-BR and en translations in v1
- **Timezone & Language Storage**: Both timezone and language are detected from browser and stored in user record during authentication callback

---

## 2. Data Model / ERD

### 2.1 Entities

#### User

The `users` table stores local user records linked to AWS Cognito identities.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| `id` | SERIAL | PRIMARY KEY | Auto-incrementing user ID |
| `name` | VARCHAR(255) | NOT NULL | User's preferred name (from Cognito) |
| `email` | VARCHAR(255) | NOT NULL, UNIQUE | User's email address (from Cognito) |
| `cognito_id` | VARCHAR(255) | NOT NULL, UNIQUE | AWS Cognito User Sub (unique identifier from Cognito) |
| `timezone` | VARCHAR(50) | NOT NULL, DEFAULT 'America/Sao_Paulo' | User's timezone (detected from browser, e.g., 'America/Sao_Paulo') |
| `language` | VARCHAR(10) | NOT NULL, DEFAULT 'pt' | User's preferred language (detected from browser, e.g., 'pt' or 'en') |
| `created_at` | TIMESTAMP(0) | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Record creation timestamp |
| `updated_at` | TIMESTAMP(0) | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Record last update timestamp |

**Indexes:**
- Primary Key: `users_pkey` on `id`
- Unique Index: `users_email_key` on `email`
- Unique Index: `users_cognito_id_key` on `cognito_id`

**Notes:**
- `cognito_id` is set during callback processing (after Cognito authentication)
- `name` and `email` are extracted from Cognito user attributes
- `timezone` is detected from browser during authentication callback (fallback: 'America/Sao_Paulo')
  - Validated against Rails timezone list (`ActiveSupport::TimeZone.all`) in User model (see section 4.1)
- `language` is detected from browser Accept-Language header during authentication callback (fallback: 'pt')
  - Validated against Rails i18n available locales (`config.i18n.available_locales`) in User model (see section 4.1)
- Both `timezone` and `language` can be updated by the user later (not in v1 scope)
- Model-level validations ensure data integrity (see section 4.1 for details)
- No `status` field needed - Cognito handles email confirmation

#### Patient

The `patients` table links users to professionals (nutritionists). Created automatically during the authentication callback.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| `id` | SERIAL | PRIMARY KEY | Auto-incrementing patient ID |
| `user_id` | INTEGER | NOT NULL | Foreign key to users.id (CASCADE delete) |
| `professional_id` | INTEGER | NOT NULL | Reference to professional/nutritionist (no FK constraint yet) |
| `created_at` | TIMESTAMP(0) | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Record creation timestamp |
| `updated_at` | TIMESTAMP(0) | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Record last update timestamp |

**Indexes:**
- Primary Key: `patients_pkey` on `id`
- Index: `patients_user_id_idx` on `user_id` (for user lookup)
- Index: `patients_professional_id_idx` on `professional_id` (for professional lookup)
- Unique Index: `patients_user_professional_unique_idx` on `(user_id, professional_id)` (ensures one patient record per user-professional pair)

**Foreign Keys:**
- `user_id` references `users.id` with CASCADE delete (when user is deleted, all patient records are deleted)
- `professional_id` references a future professionals table (no FK constraint yet)

**Notes:**
- `professional_id` comes from validated `state` parameter in Cognito callback (after CSRF validation)
- **REQUIRED**: `professional_id` must be present in state parameter, otherwise patient record creation fails and authentication is aborted (no fallback to Professional.first)
- Both User and Patient records are created automatically during callback (onboarding flow to be implemented in the future)
- One user can have multiple patient records (one per professional)
- Patient record creation uses `find_or_create_by!` to ensure uniqueness and handle race conditions

### 2.2 Entity Relationship Diagram

```
┌─────────────────────────────────────┐
│           AWS Cognito               │
│  (Hosted UI - Login/Signup Forms)   │
│                                     │
│  - User Sub (cognito_id)            │
│  - Email                             │
│  - Name                              │
│  - Password (hashed)                 │
│  - Access Tokens (JWT)               │
│  - Refresh Tokens                    │
└──────────────┬──────────────────────┘
               │
               │ Linked via cognito_id
               │
┌──────────────▼──────────────────────┐
│            users                     │
├─────────────────────────────────────┤
│ PK  id              SERIAL           │
│     name            VARCHAR(255)     │
│     email           VARCHAR(255) UNIQUE
│     cognito_id      VARCHAR(255) UNIQUE
│     timezone        VARCHAR(50)      │
│     language        VARCHAR(10)      │
│     created_at      TIMESTAMP        │
│     updated_at      TIMESTAMP        │
└──────────────┬──────────────────────┘
               │
               │ Referenced by user_id
               │ (FK with CASCADE delete)
               │
┌──────────────▼──────────────────────┐
│          patients                   │
├─────────────────────────────────────┤
│ PK  id              SERIAL           │
│     user_id         INTEGER          │
│     professional_id INTEGER         │
│     created_at      TIMESTAMP        │
│     updated_at      TIMESTAMP        │
└─────────────────────────────────────┘
```

**Notes:**
- `cognito_id` links users to Cognito identities
- `user_id` in patients table references users.id with CASCADE delete (FK constraint)
- `professional_id` links patients to nutritionists (no FK constraint yet)
- One user can have multiple patient records (one per professional relationship)

---

## 3. Database Schema

### 3.1 Users Table

**Table Name**: `users`

**Migration**: `000001_create_users_table.up.sql`

```sql
-- Create users table
CREATE TABLE IF NOT EXISTS "users" (
  "id" SERIAL NOT NULL,
  "name" VARCHAR(255) NOT NULL,
  "email" VARCHAR(255) NOT NULL,
  "cognito_id" VARCHAR(255) NOT NULL,
  "timezone" VARCHAR(50) NOT NULL DEFAULT 'America/Sao_Paulo',
  "language" VARCHAR(10) NOT NULL DEFAULT 'pt',
  "created_at" TIMESTAMP(0) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(0) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- Create indexes
CREATE UNIQUE INDEX IF NOT EXISTS "users_email_key" ON "users"("email");
CREATE UNIQUE INDEX IF NOT EXISTS "users_cognito_id_key" ON "users"("cognito_id");
```

**Field Descriptions:**
- **id**: Primary key, auto-incrementing integer
- **name**: User's display name (from Cognito `name` attribute)
- **email**: User's email address, must be unique, used for login
- **cognito_id**: AWS Cognito User Sub identifier, must be unique
- **timezone**: User's timezone (e.g., 'America/Sao_Paulo'), detected from browser during callback, defaults to 'America/Sao_Paulo'
- **language**: User's preferred language ('pt' or 'en'), detected from browser Accept-Language header during callback, defaults to 'pt'
- **created_at**: Timestamp when user record was created
- **updated_at**: Timestamp when user record was last modified

### 3.2 Patients Table

**Table Name**: `patients`

**Migration**: `000002_create_patients_table.up.sql` (new)

```sql
-- Create patients table
CREATE TABLE IF NOT EXISTS "patients" (
  "id" SERIAL NOT NULL,
  "user_id" INTEGER NOT NULL,
  "professional_id" INTEGER NOT NULL,
  "created_at" TIMESTAMP(0) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(0) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "patients_pkey" PRIMARY KEY ("id")
);

-- Create indexes
CREATE INDEX IF NOT EXISTS "patients_user_id_idx" ON "patients"("user_id");
CREATE INDEX IF NOT EXISTS "patients_professional_id_idx" ON "patients"("professional_id");
CREATE UNIQUE INDEX IF NOT EXISTS "patients_user_professional_unique_idx" ON "patients"("user_id", "professional_id");
```

**Field Descriptions:**
- **id**: Primary key, auto-incrementing integer
- **user_id**: Foreign key to users.id with CASCADE delete
- **professional_id**: Reference to professional/nutritionist (no FK constraint yet)
- **created_at**: Timestamp when patient record was created
- **updated_at**: Timestamp when patient record was last modified

**Foreign Keys:**
- `user_id` references `users.id` with CASCADE delete (when user is deleted, all patient records are deleted)

**Notes:**
- Created during authentication callback
- **REQUIRED**: `professional_id` must be present in state parameter, otherwise patient record creation fails and authentication is aborted (no fallback)
- **Unique constraint**: The unique index `patients_user_professional_unique_idx` ensures one patient record per user-professional pair at the database level (defense in depth - also validated in Rails model, see section 4.2)

---

## 4. Rails Models

### 4.1 User Model

**File**: `app/models/user.rb`

```ruby
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
```

**Validations:**
- **timezone**: Must be present and must be a valid IANA timezone identifier (e.g., "America/Sao_Paulo")
  - Uses `TZInfo::Timezone.get(timezone)` to validate IANA format
  - This matches the format returned by JavaScript `Intl.DateTimeFormat().resolvedOptions().timeZone`
- **language**: Must be present and must be one of the available locales configured in Rails (`config.i18n.available_locales`)

**Notes:**
- Timezone validation uses TZInfo to validate IANA timezone identifiers (standard format from JavaScript)
- Language validation uses Rails i18n configuration (`Rails.application.config.i18n.available_locales`)
- These validations ensure data integrity at the model level (not at database level)
- Invalid timezone or language values will raise validation errors before saving

### 4.2 Patient Model

**File**: `app/models/patient.rb`

```ruby
class Patient < ApplicationRecord
  # Associations
  belongs_to :user
  # belongs_to :professional  # Uncomment when Professional model is created

  # Validations
  validates :user_id, uniqueness: { scope: :professional_id, message: "already has a patient record for this professional" }
end
```

**Validations:**
- **user_id + professional_id**: Unique constraint ensures one patient record per user-professional pair
  - **Model-level validation**: Rails validation prevents duplicates at application level
  - **Database-level constraint**: Unique index `patients_user_professional_unique_idx` enforces uniqueness at database level (see section 3.2)
  - **Defense in depth**: Both validations ensure data integrity even if Rails validations are bypassed (e.g., `save(validate: false)` or direct SQL inserts)

---

## 5. Authentication Flow

### 5.1 Overview

The authentication flow uses **Cognito Hosted UI** for all user-facing authentication forms. The frontend redirects users to Cognito, and Cognito redirects back to a callback endpoint after authentication.

### 5.2 Sign Up Flow (New User)

```
1. User navigates to /auth/sign_up?professional_id=XX
   ↓
2. Rails generates CSRF token and stores in session:
   - Generates secure random token (32 bytes, base64url encoded)
   - Stores in session[:oauth_state]
   - Builds state parameter: csrf_token=XXX&professional_id=XX
   ↓
3. Rails redirects to Cognito Hosted UI (Managed Login V2):
   https://{domain}.auth.{region}.amazoncognito.com/oauth2/authorize?
     client_id={CLIENT_ID}&
     response_type=code&
     redirect_uri={CALLBACK_URI}&
     scope=openid email profile&
     state=csrf_token%3DXXX%26professional_id%3DXX
   (Language determined by Accept-Language header, not query parameter)
   ↓
4. Cognito Managed Login V2 redirects to /signup page
   ↓
5. User completes signup in Cognito Hosted UI
   - Enters name, email, password (all handled by Cognito)
   - Cognito validates password policy
   - Cognito sends confirmation email
   ↓
6. User confirms email in Cognito Hosted UI (handled by Cognito)
   ↓
7. Cognito redirects to callback:
   https://app.balansi.me/auth/callback?
     code={AUTHORIZATION_CODE}&
     state=csrf_token%3DXXX%26professional_id%3DXX
   ↓
8. Rails callback endpoint:
   - Validates CSRF token from state parameter (prevents CSRF attacks)
   - Checks authorization code idempotency (prevents replay attacks)
   - Exchanges code for tokens using Cognito
   - Verifies ID token signature using Cognito JWKS
   - Extracts user info from ID token (preferred) or userinfo endpoint (fallback)
   - Creates user record in database (if doesn't exist)
   - Creates patient record (user_id, professional_id) - REQUIRED, fails if professional_id missing
   - Creates Rails session with httpOnly cookie
   - Marks authorization code as processed (idempotency)
   - Redirects to home (onboarding to be implemented later)
```

### 5.3 Sign In Flow (Existing User)

```
1. User navigates to protected route or clicks login link
   ↓
2. Rails checks for valid session (httpOnly cookie)
   ↓
3. If no valid session, redirects to /auth/sign_in
   ↓
4. Rails generates CSRF token and stores in session:
   - Generates secure random token (32 bytes, base64url encoded)
   - Stores in session[:oauth_state]
   - Builds state parameter: csrf_token=XXX (optional: &professional_id=XX)
   ↓
5. Rails redirects to Cognito Hosted UI (Managed Login V2):
   https://{domain}.auth.{region}.amazoncognito.com/oauth2/authorize?
     client_id={CLIENT_ID}&
     response_type=code&
     redirect_uri={CALLBACK_URI}&
     scope=openid email profile&
     state=csrf_token%3DXXX
   (Language determined by Accept-Language header, not query parameter)
   ↓
6. Cognito Managed Login V2 redirects to /login page
   ↓
7. User enters email/password in Cognito Hosted UI (handled by Cognito)
   ↓
8. Cognito validates credentials
   ↓
9. Cognito redirects to callback:
   https://app.balansi.me/auth/callback?
     code={AUTHORIZATION_CODE}&
     state=csrf_token%3DXXX
   ↓
10. Rails callback endpoint:
    - Validates CSRF token from state parameter (prevents CSRF attacks)
    - Checks authorization code idempotency (prevents replay attacks)
    - Exchanges code for tokens using Cognito
    - Verifies ID token signature using Cognito JWKS
    - Extracts user info from ID token (preferred) or userinfo endpoint (fallback)
    - Finds or creates user record
    - Creates patient record if professional_id in state (REQUIRED - fails if missing)
    - Creates Rails session with httpOnly cookie
    - Marks authorization code as processed (idempotency)
    - Redirects to home
```

### 5.4 Password Recovery Flow

Password recovery is handled entirely by Cognito Hosted UI. Users click "Forgot Password" in the Cognito login form, and Cognito handles the entire flow (email verification, password reset).

---

## 6. Rails Routes and Controllers

### 6.1 Callback Endpoint

**Route**: `GET /auth/callback`

**Controller**: `Auth::CallbacksController#show`

**Purpose**: Handles Cognito Hosted UI redirect after authentication.

**Query Parameters:**
- `code` (required): Authorization code from Cognito
- `state` (optional): State parameter containing `professional_id=XX`

**Processing Steps:**
1. **CSRF Protection**: Validate state parameter contains valid CSRF token:
   ```ruby
   # Validates CSRF token stored in session matches token in state parameter
   # Uses constant-time comparison to prevent timing attacks
   validate_state_parameter(params[:state])
   ```
2. **Idempotency Check**: Verify authorization code hasn't been processed:
   ```ruby
   # Prevents replay attacks - codes can only be used once
   check_code_idempotency
   ```
3. **Extract Validated State**: Extract business parameters (e.g., professional_id) from validated state:
   ```ruby
   # Removes CSRF token, keeps only business parameters
   validated_state = extract_validated_state(params[:state])
   ```
4. **Run SignUpInteraction**: Delegates business logic to interaction:
   ```ruby
   result = Auth::SignUpInteraction.run(
     code: params[:code],
     state: validated_state,
     timezone: detect_browser_timezone,
     language: detect_browser_language.to_s
   )
   ```
   The interaction handles:
   - Exchange code for tokens using CognitoService
   - Validate all required tokens are present (access_token, id_token, refresh_token)
   - Verify ID token signature using Cognito JWKS (with caching)
   - Extract user info from ID token (preferred) or userinfo endpoint (fallback)
   - Find or create user record with timezone and language (only set on creation)
   - Create patient record with professional_id from state (REQUIRED - fails if missing)
5. **Mark Code as Processed**: Store authorization code as processed (idempotency):
   ```ruby
   # Cache code with 5-minute expiration
   mark_code_as_processed(result)
   ```
6. **Handle Result**: Create session on success, show error on failure:
   ```ruby
   if result.valid? && result.result.present?
     session[:user_id] = result.result[:user].id
     session[:refresh_token] = result.result[:refresh_token]
     reset_session  # Regenerates session ID (prevents session fixation)
     redirect_to root_path
   else
     render :error, status: :unprocessable_entity
   end
   ```

**Response**: Redirect to home page

**Error Handling:**
- **Invalid state (CSRF)**: Returns 403 Forbidden with error view
- **Code already processed**: Returns 400 Bad Request (idempotency check)
- **Invalid authorization code**: Logs error, renders error view with appropriate message
- **Token exchange failure**: Logs error, renders error view (handles invalid_grant specifically)
- **ID token verification failure**: Logs error, renders error view
- **Missing professional_id**: Logs error, renders error view (patient record creation fails)
- **User creation failure**: Logs error with details, renders error view
- **Unexpected exceptions**: Logs full backtrace, renders generic error view (production shows generic message)

### 6.2 Sign In/Sign Up Endpoint

**Routes**: 
- `GET /auth/sign_in` - Login
- `GET /auth/sign_up` - Registration

**Controller**: `Auth::SessionsController#new`

**Purpose**: Initiate OAuth authentication flow by generating CSRF token and redirecting to Cognito.

**Processing:**
1. Generate CSRF token:
   ```ruby
   csrf_token = SecureRandom.urlsafe_base64(32)
   session[:oauth_state] = csrf_token
   ```
2. Build state parameter with CSRF token and optional professional_id:
   ```ruby
   state_params = { csrf_token: csrf_token }
   state_params[:professional_id] = params[:professional_id] if params[:professional_id].present?
   state = URI.encode_www_form(state_params)
   ```
3. Detect browser language and redirect to appropriate Cognito endpoint:
   ```ruby
   locale = detect_browser_language
   if request.path == "/auth/sign_up"
     redirect_to CognitoService.signup_url(state: state, locale: locale), allow_other_host: true
   else
     redirect_to CognitoService.login_url(state: state, locale: locale), allow_other_host: true
   end
   ```

### 6.3 Sign Out Endpoint

**Route**: `DELETE /auth/sign_out`

**Controller**: `Auth::SessionsController#destroy`

**Purpose**: Sign out user by clearing Rails session and redirecting to Cognito logout.

**Processing:**
1. Clear Rails session (regenerates session ID, prevents session fixation):
   ```ruby
   reset_session
   ```
2. Redirect to Cognito logout URL (invalidates Cognito session as well):
   ```ruby
   # Normalizes logout_uri with trailing slash to match Terraform configuration
   redirect_to CognitoService.logout_url, allow_other_host: true, status: :see_other
   ```
3. After Cognito logout, user is redirected back to logout_uri (configured in credentials, typically app root)

### 6.4 Current User Helper

**Method**: `current_user` (ApplicationController concern)

**Purpose**: Get current authenticated user from session.

**Implementation:**
```ruby
module Authentication
  extend ActiveSupport::Concern

  included do
    helper_method :current_user
    before_action :authenticate_user!
  end

  private

  def current_user
    @current_user ||= User.find(session[:user_id]) if session[:user_id]
  rescue ActiveRecord::RecordNotFound
    # User was deleted but session still has user_id
    # Clear invalid session and return nil
    session.delete(:user_id)
    session.delete(:refresh_token)
    nil
  end

  def authenticate_user!
    redirect_to auth_login_path unless current_user
  end
end
```

**Session Data:**
- **Session Storage**: `session[:user_id]` and `session[:refresh_token]` are stored in the session cookie
  - `user_id`: Used to identify the current authenticated user
  - `refresh_token`: Stored for future token refresh functionality (not used in v1, but stored to avoid logout when implementing token refresh)
- **Cognito ID Access**: When needed, access via `current_user.cognito_id` (stored in database)
- **Benefits**: Minimal data in session, refresh_token stored for future compatibility

**Usage in Controllers:**
```ruby
class ApplicationController < ActionController::Base
  include Authentication
end
```

**Note**: Authentication is required by default for all controllers. Controllers that need public access (like auth callbacks) should use `skip_before_action :authenticate_user!`:
```ruby
class Auth::CallbacksController < ApplicationController
  skip_before_action :authenticate_user!
  # ... rest of controller
end
```

---

## 7. Rails Session Management

### 7.1 Session Configuration

Rails session is configured to use httpOnly cookies by default. Configuration in `config/application.rb`:

```ruby
config.session_store :cookie_store,
  key: '_balansi_session',
  expire_after: 30.days  # Align with Cognito refresh_token_validity (30 days)
```

**Note**: Rails sets `httponly: true` by default. `secure` and `same_site` are configured via `config.force_ssl` and session cookie settings in production environment.

**Session Expiration:**
- **Expire After**: `30.days` - Aligned with Cognito `refresh_token_validity`
- **Rationale**: Since we store the `refresh_token` in the session, the session should remain valid as long as the refresh token is valid
- **Refresh Token**: Stored in session for future token refresh functionality (not used in v1, but session remains valid for 30 days)
- **Access Token**: Expires after 1 hour, but user session remains valid for 30 days (refresh_token can be used to get new access tokens)
- **Session Renewal**: Not implemented in v1 - user session expires after 30 days, requiring re-authentication

**Session Security:**
- **HttpOnly**: `true` (prevents JavaScript access - default in Rails)
- **Secure**: `true` in production (HTTPS only)
- **SameSite**: `Lax` (CSRF protection)
- **Encryption**: Rails automatically encrypts session data

### 7.2 Authentication Before Action

**File**: `app/controllers/application_controller.rb`

```ruby
class ApplicationController < ActionController::Base
  include Authentication
  include BrowserLanguage
  include BrowserTimezone

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes
end
```

**Concerns:**

**BrowserLanguage** (`app/controllers/concerns/browser_language.rb`):
- Detects language from Accept-Language header
- Returns locale symbol (:pt or :en), defaults to :pt
- Sets Rails locale automatically via `before_action :set_locale`
- Provides `helper_method :detect_browser_language` for views

**BrowserTimezone** (`app/controllers/concerns/browser_timezone.rb`):
- Detects timezone from cookies (set by JavaScript)
- Returns timezone string in IANA format (e.g., 'America/Sao_Paulo')
- Defaults to 'America/Sao_Paulo' if cookie not present
- Provides `helper_method :detect_browser_timezone` for views

### 7.3 Route Protection

**File**: `config/routes.rb`

```ruby
Rails.application.routes.draw do
  # Health check endpoint
  get "up" => "rails/health#show", as: :rails_health_check

  # Auth routes
  get "/auth/callback", to: "auth/callbacks#show"
  get "/auth/sign_up", to: "auth/sessions#new"
  get "/auth/sign_in", to: "auth/sessions#new", as: :auth_login_path
  delete "/auth/sign_out", to: "auth/sessions#destroy"

  # Home route
  get "home/index"
  root "home#index"
end
```

---

## 8. Cognito Client Service

### 8.1 Cognito Service

**File**: `app/services/cognito_service.rb`

```ruby
class CognitoService
  # Use Rails credentials instead of environment variables
  # Load credentials lazily to handle cases where they're not yet configured

  # Get credentials for the current environment
  def self.credentials
    Rails.application.credentials(Rails.env.to_sym)
  rescue ArgumentError
    # Fallback to default credentials if environment-specific doesn't exist
    Rails.application.credentials
  end

  def self.exchange_code_for_tokens(code)
    # Exchanges authorization code for access_token, id_token, and refresh_token
    # Returns hash with tokens or error hash on failure
  end

  def self.get_user_info(access_token)
    # Retrieves user information from Cognito userinfo endpoint
    # Returns hash with sub, email, name, etc.
    # Note: Prefer using decode_id_token which extracts info from JWT
  end

  def self.decode_id_token(id_token)
    # Decodes and verifies ID token (JWT) using Cognito's public keys (JWKS)
    # Verifies JWT signature, expiration, issued-at, audience, and issuer
    # Caches JWKS for 1 hour to avoid fetching on every verification
    # Returns decoded payload hash or empty hash on failure
  end

  def self.login_url(state: nil, locale: :pt)
    # Uses Managed Login V2 endpoint (/oauth2/authorize) which redirects to /login
    # Language is determined by Accept-Language header (not query parameter)
    # Returns full Cognito OAuth authorization URL
  end

  def self.signup_url(state: nil, locale: :pt)
    # Uses Managed Login V2 endpoint (/oauth2/authorize) which redirects to /signup
    # Language is determined by Accept-Language header (not query parameter)
    # Returns full Cognito OAuth authorization URL
  end

  def self.logout_url(logout_uri_param: nil)
    # Normalizes logout_uri to ensure trailing slash matches Terraform config
    # Uses logout_uri from credentials or fallback to redirect_uri
    # Returns full Cognito logout URL
  end

  def self.cognito_language_code(locale)
    # Converts browser locale to Cognito language code
    # Returns "pt-BR" or "en", defaults to "pt-BR"
  end

  private

  def self.cognito_credentials
    credentials.dig(:cognito) || {}
  end

  def self.credentials_configured?
    cognito_credentials.present?
  end

  def self.base_url
    "https://#{cognito_credentials[:domain]}.auth.#{cognito_credentials[:region]}.amazoncognito.com"
  end

  def self.token_url
    "#{base_url}/oauth2/token"
  end

  def self.userinfo_url
    "#{base_url}/oauth2/userInfo"
  end

  def self.jwks_url
    "https://cognito-idp.#{cognito_credentials[:region]}.amazonaws.com/#{cognito_credentials[:user_pool_id]}/.well-known/jwks.json"
  end

  def self.fetch_jwks
    # Fetches JWKS from Cognito with 1-hour caching
  end

  class MissingCredentialsError < StandardError; end
end
```

---

## 9. Browser Timezone Detection (Frontend)

### 9.1 Timezone Detection Script

Since we're using Rails views, we need JavaScript to detect the browser timezone and send it to the server via cookie.

**File**: `app/javascript/application.js` or `app/assets/javascripts/timezone.js`

```javascript
// Detect browser timezone and store in cookie
(function() {
  try {
    const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
    // Store timezone in a cookie that can be read by Rails
    document.cookie = `timezone=${encodeURIComponent(timezone)}; path=/; max-age=${60 * 60 * 24 * 365}`; // 1 year
  } catch (e) {
    console.warn('Could not detect timezone:', e);
    // Cookie will default to 'America/Sao_Paulo' in ApplicationController
  }
})();
```

**Note**: The cookie approach is recommended because:
- Works for all requests, including redirects from Cognito callback
- Persists across page reloads
- No need to intercept fetch/XMLHttpRequest
- Rails can easily read cookies server-side

**Include in Rails layout:**

```erb
<!-- app/views/layouts/application.html.erb -->
<%= javascript_include_tag "timezone" if request.format.html? %>
```

Or in the main JavaScript bundle if using importmaps/webpack/etc.

---

## 10. Rails Views and Redirects

### 10.1 Auth Controller

**File**: `app/controllers/auth/sessions_controller.rb`

```ruby
class Auth::SessionsController < ApplicationController
  skip_before_action :authenticate_user!

  def new
    # Generate CSRF token and store in session for validation on callback
    csrf_token = generate_state_token
    session[:oauth_state] = csrf_token

    # Build state parameter: CSRF token + optional professional_id
    state_params = { csrf_token: csrf_token }
    state_params[:professional_id] = params[:professional_id] if params[:professional_id].present?
    state = URI.encode_www_form(state_params)

    locale = detect_browser_language

    # Determine if this is a sign-up or sign-in request
    if request.path == "/auth/sign_up"
      redirect_to CognitoService.signup_url(state: state, locale: locale), allow_other_host: true
    else
      redirect_to CognitoService.login_url(state: state, locale: locale), allow_other_host: true
    end
  rescue CognitoService::MissingCredentialsError => e
    render :new, status: :service_unavailable
  end

  def destroy
    # Clear Rails session first (regenerates session ID, prevents session fixation)
    reset_session

    # Redirect to Cognito logout to invalidate Cognito session
    redirect_to CognitoService.logout_url, allow_other_host: true, status: :see_other
  rescue CognitoService::MissingCredentialsError => e
    # If Cognito service is not configured, just redirect to home
    redirect_to root_path, status: :see_other
  end

  private

  # Generate a secure random token for CSRF protection
  def generate_state_token
    SecureRandom.urlsafe_base64(32)
  end
end
```

### 10.2 Callback Controller

**File**: `app/controllers/auth/callbacks_controller.rb`

```ruby
class Auth::CallbacksController < ApplicationController
  skip_before_action :authenticate_user!
  before_action :validate_csrf_protection, :check_code_idempotency

  def show
    validated_state = extract_validated_state(params[:state])
    result = run_sign_up_interaction(validated_state)

    mark_code_as_processed(result)
    handle_authentication_result(result)
  rescue => e
    handle_authentication_exception(e)
  end

  private

  def validate_csrf_protection
    # Validates CSRF token from state parameter using constant-time comparison
    # Returns 403 Forbidden if validation fails
  end

  def check_code_idempotency
    # Checks if authorization code has already been processed
    # Returns 400 Bad Request if code was already used
  end

  def extract_validated_state(state)
    # Extracts business parameters (e.g., professional_id) from validated state
    # Removes CSRF token before passing to interaction
  end

  def mark_code_as_processed(result)
    # Marks authorization code as processed (cached for 5 minutes)
    # Prevents replay attacks
  end

  def handle_authentication_result(result)
    # Creates session on success, renders error view on failure
  end

  def handle_authentication_exception(exception)
    # Logs exception with backtrace, renders error view
    # In production, shows generic message (no information leakage)
  end
end
```

**Security Features:**
- CSRF protection via state parameter validation
- Authorization code idempotency check (prevents replay attacks)
- Constant-time token comparison (prevents timing attacks)
- One-time use CSRF tokens (cleared after validation)
- Generic error messages in production (no information leakage)
- Comprehensive error logging for debugging

**Notes:**
- Controller validates CSRF protection and idempotency before delegating to interaction
- Business logic is delegated to `Auth::SignUpInteraction`
- Error handling is comprehensive with appropriate HTTP status codes
- Session creation includes `reset_session` to prevent session fixation

### 10.3 Sign Up Interaction

**File**: `app/interactions/auth/sign_up_interaction.rb`

**Required Gems** - Add to `Gemfile`:
```ruby
gem 'active_interaction', '~> 5.0'  # Service objects pattern for business logic
gem 'jwt', '~> 3.1'                  # JWT token verification
gem 'rack-attack'                    # Rate limiting middleware
gem 'httparty'                       # HTTP client for Cognito API calls
gem 'tzinfo'                         # IANA timezone validation (usually included with Rails)
```

**Note**: `httparty`, `tzinfo`, and `jwt` are already included in most Rails setups, but explicitly add them if not present.

**Interaction Implementation:**

```ruby
module Auth
  class SignUpInteraction < ActiveInteraction::Base
    string :code
    string :state, default: nil
    string :timezone, default: nil
    string :language, default: nil

    validates :code, presence: true

    def execute
      # Exchange code for tokens (handles errors internally)
      tokens = exchange_code_for_tokens
      return nil unless tokens

      # Extract and validate tokens
      access_token = tokens["access_token"]
      id_token = tokens["id_token"]
      refresh_token = tokens["refresh_token"]

      return nil unless validate_tokens(access_token, id_token, refresh_token)

      # Retrieve user information from Cognito (ID token preferred, userinfo as fallback)
      user_info = retrieve_user_info(id_token, access_token)

      # Validate user information is complete
      return nil unless user_info_valid?(user_info)

      # Detect timezone and language from browser (defaults for new users)
      detected_timezone = timezone || "America/Sao_Paulo"
      detected_language = language || "pt"

      # Find or create user (adds errors to errors object on failure)
      user = find_or_create_user(user_info, detected_timezone, detected_language)
      return nil unless user

      # Create patient record (required - authentication fails if this fails)
      return nil unless create_patient_record(user)

      # Return result hash with user and refresh_token
      { user: user, refresh_token: refresh_token }
    end

    private

    def exchange_code_for_tokens
      # Exchanges authorization code for tokens
      # Handles token exchange errors with appropriate error messages
    end

    def validate_tokens(access_token, id_token, refresh_token)
      # Validates that all required tokens are present
      # Returns true if all tokens present, false otherwise (adds errors)
    end

    def retrieve_user_info(id_token, access_token)
      # Tries ID token first (contains all necessary claims, verified signature)
      # Falls back to userinfo endpoint if ID token doesn't work
      # Returns hash with sub, email, and name keys
    end

    def user_info_valid?(user_info)
      # Validates that user_info contains required fields (sub and email)
      # Returns true if valid, false otherwise (adds errors)
    end

    def find_or_create_user(user_info, detected_timezone, detected_language)
      # Finds or creates user in database based on Cognito user info
      # Sets timezone and language only on initial creation
      # Returns User instance on success, nil on failure (errors added)
    end

    def create_patient_record(user)
      # Creates patient record for user (required - authentication fails if this fails)
      # Extracts professional_id from state parameter
      # REQUIRED: professional_id must be present in state, otherwise fails
      # Returns true on success, false on failure (errors added)
    end

    def parse_professional_id
      # Parses professional_id from state parameter
      # Returns professional_id string or nil if not present or invalid
    end
  end
end
```

**Key Improvements from ERD:**
- ID token signature verification using Cognito JWKS (with caching)
- Prefer ID token over userinfo endpoint (more efficient, already verified)
- Validates all required tokens (access_token, id_token, refresh_token)
- Consistent error handling pattern (all errors added to errors object)
- Professional ID is REQUIRED (no fallback to Professional.first)
- Extracted methods for better maintainability and testability

**Benefits of using ActiveInteraction:**
- **Thin Controllers**: Business logic is encapsulated in interactions
- **Reusability**: Interactions can be reused in different contexts (controllers, jobs, etc.)
- **Testability**: Interactions are easy to test in isolation
- **Validation**: ActiveInteraction provides built-in validation for inputs
- **Error Handling**: Clear error messages and validation errors
- **Service Objects Pattern**: Follows service object pattern for business logic

**Usage:**
```ruby
# In controller
result = Auth::SignUpInteraction.run(code: params[:code], state: params[:state])

if result.valid?
  # Use result.user, result.refresh_token
else
  # Handle errors: result.errors.full_messages
end
```

---

## 11. Cognito Configuration

### 11.1 User Pool Client Settings

**All settings configured via Terraform:**

**Allowed OAuth Flows:**
- Authorization code grant
- Implicit grant (optional)

**Allowed OAuth Scopes:**
- `openid`
- `email`
- `profile`

**Allowed Callback URLs:**
- `https://app.balansi.me/auth/callback` (production)
- `http://localhost:3000/auth/callback` (development)

**Allowed Sign-out URLs:**
- `https://app.balansi.me/` (production)
- `http://localhost:3000/` (development)

**Token Validity:**
- Access token: 1 hour
- ID token: 1 hour
- Refresh token: 30 days (matches Rails session expiration)

**Note**: All these settings are configured in the Terraform Cognito module. No manual configuration via AWS Console is needed or recommended.

### 11.2 Hosted UI Domain and Managed Login V2

**Configured via Terraform:**
- Custom domain: `auth.balansi.me` (production)
- Or use Cognito default: `{pool-name}.auth.{region}.amazoncognito.com` (development)
- Domain configuration is managed in Terraform module
- **Managed Login V2**: Uses `/oauth2/authorize` endpoint which automatically redirects to `/login` or `/signup` based on context
- Language is determined by `Accept-Language` HTTP header (not query parameter)
- Branding and styling can be configured via AWS Console or AWS CLI (not Terraform yet)

**Managed Login V2 Notes:**
- The `/oauth2/authorize` endpoint is used for both login and signup
- Cognito automatically shows the appropriate page (`/login` or `/signup`) based on context
- Language localization is handled via `Accept-Language` header (pt-BR or en)
- The `lang` query parameter is not supported in Managed Login V2

### 11.3 Configuring Sign-up Form Fields (Including "name")

**✅ All Cognito configuration must be done via Terraform** - This ensures infrastructure as code, version control, and consistency across environments.

**Using Terraform (Required):**

```hcl
resource "aws_cognito_user_pool" "main" {
  name = "balansi-users"

  schema {
    name                = "name"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }
}

# Configure Sign-up experience
resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.project_name}-${var.environment}-client"
  user_pool_id = aws_cognito_user_pool.main.id

  # ... other client settings
}
```

**Note**: Standard attributes like "name" are already available in Cognito. The Terraform module configures:
1. "name" as required attribute in the User Pool schema
2. All OAuth settings, callback URLs, and token validity periods
3. Cognito domain configuration
4. All necessary settings for development, staging, and production environments

#### Development Setup (Real AWS Cognito via Terraform)

**For Development, use real AWS Cognito created via Terraform:**

1. **Create Cognito with Terraform:**
   ```bash
   cd terraform/environments/dev
   terraform init
   terraform plan
   terraform apply
   ```

2. **The Terraform module configures:**
   - User Pool with "name" and "email" as required attributes
   - User Pool Client with OAuth settings
   - Cognito domain (default domain, not custom)
   - All necessary configurations for development

3. **Get Terraform outputs and update Rails credentials:**
   ```bash
   # Get outputs
   terraform output -json
   
   # Update Rails credentials
   bin/rails credentials:edit --environment development
   # Add cognito values from Terraform outputs
   ```

4. **Terraform handles all configuration:**
   - No need for AWS CLI scripts
   - No need for manual Console configuration
   - Infrastructure is version controlled
   - Easy to recreate or update

**Important Notes:**
- Standard attributes (`name`, `email`, `phone_number`, etc.) are built-in to Cognito
- Custom attributes require the `custom:` prefix (e.g., `custom:professional_id`)
- Terraform module configures "name" as required attribute in the schema
- Required attributes will appear in the Hosted UI sign-up form
- All Cognito configuration is managed via Terraform

**For Existing User Pools:**
- If you have an existing User Pool created manually, migrate it to Terraform
- Use `terraform import` to import existing resources into Terraform state
- Or recreate the User Pool via Terraform (users will need to re-authenticate)
- See Terraform documentation for importing Cognito resources
- **All future configuration changes must be done via Terraform** - no manual Console configuration

---

## 12. Configuration Management

### 12.1 Rails Credentials (Recommended)

**Use Rails credentials instead of environment variables** - This is the Rails-native way to manage secrets without adding external dependencies.

**File**: `config/credentials.yml.enc` (encrypted, version controlled)
**Key File**: `config/master.key` (NOT version controlled, keep secure)

**Edit credentials:**
```bash
# Edit credentials for current environment
bin/rails credentials:edit

# Edit credentials for specific environment
EDITOR="code --wait" bin/rails credentials:edit --environment development
EDITOR="code --wait" bin/rails credentials:edit --environment staging
EDITOR="code --wait" bin/rails credentials:edit --environment production
```

**Example credentials structure** (`config/credentials.yml.enc`):

```yaml
# Development credentials (config/credentials/development.yml.enc)
cognito:
  user_pool_id: sa-east-1_XXXXXXXXX  # From Terraform output
  client_id: xxxxxxxxxxxxxxxxxxxxx    # From Terraform output
  client_secret: xxxxxxxxxxxxxxxxxxxxxx  # From Terraform output (if client has secret)
  domain: balansi-dev-xxxxx.auth.sa-east-1.amazoncognito.com  # From Terraform output
  region: sa-east-1
  redirect_uri: http://localhost:3000/auth/callback
  logout_uri: http://localhost:3000  # Optional, defaults to redirect_uri if not set

database:
  url: postgresql://balansi_dev_user:password@localhost:5432/balansi_dev  # From Terraform postgresql-local module output

secret_key_base: your_secret_key_base_here
```

**Access in code:**
```ruby
# CognitoService uses lazy credential loading
def self.credentials
  Rails.application.credentials(Rails.env.to_sym)
rescue ArgumentError
  Rails.application.credentials  # Fallback to default
end

def self.cognito_credentials
  credentials.dig(:cognito) || {}
end

# Credentials are accessed via cognito_credentials method:
cognito_credentials[:user_pool_id]
cognito_credentials[:client_id]
cognito_credentials[:client_secret]
cognito_credentials[:domain]
cognito_credentials[:region]
cognito_credentials[:redirect_uri]
cognito_credentials[:logout_uri]  # Optional, falls back to redirect_uri
```

**CognitoService Implementation:**
- Uses lazy credential loading to handle cases where credentials aren't configured yet
- Provides `credentials_configured?` method to check if credentials are available
- Raises `MissingCredentialsError` if credentials are missing when required
- Supports environment-specific credentials (development, staging, production)

### 12.2 Environment-Specific Credentials

**Development Environment:**
- Uses `config/credentials/development.yml.enc`
- Cognito created via Terraform in AWS (real Cognito, not local)
- Local PostgreSQL (Homebrew) - database and user created via Terraform PostgreSQL provider
- Uses Terraform outputs to populate credentials
- Master key stored locally (not in version control)

**Staging Environment:**
- Uses `config/credentials/staging.yml.enc`
- Cognito created via Terraform in AWS
- Database: Uses shared RDS instance (database `balansi_staging`, user `balansi_staging_user`)
- Terraform outputs stored in CI/CD secrets or AWS Secrets Manager
- Master key stored in CI/CD secrets

**Production Environment:**
- Uses `config/credentials/production.yml.enc`
- Cognito created via Terraform in AWS
- Database: Uses shared RDS instance (database `balansi_production`, user `balansi_production_user`)
- Terraform outputs stored in AWS Secrets Manager or CI/CD secrets
- Master key stored in AWS Secrets Manager or CI/CD secrets

### 12.3 Integration with Terraform

**Workflow for Development:**

1. **Create Cognito with Terraform:**
   ```bash
   cd terraform/environments/dev
   terraform init
   terraform plan
   terraform apply
   ```

2. **Get Terraform outputs:**
   ```bash
   terraform output -json > ../../outputs/dev.json
   ```

3. **Create local PostgreSQL database and user:**
   ```bash
   # Terraform will create database and user using PostgreSQL provider
   # This happens automatically when you run terraform apply
   ```

4. **Update Rails credentials with Terraform outputs:**
   ```bash
   # Manually edit credentials with values from Terraform outputs
   bin/rails credentials:edit --environment development
   
   # Add:
   # - Cognito values from cognito module outputs
   # - Database URL from postgresql-local module output
   
   # Or use a script to automate (optional):
   # scripts/update_credentials_from_terraform.rb
   ```

5. **Terraform outputs structure (Development):**
   ```json
   {
     "cognito_user_pool_id": {
       "value": "sa-east-1_XXXXXXXXX"
     },
     "cognito_client_id": {
       "value": "xxxxxxxxxxxxxxxxxxxxx"
     },
     "cognito_client_secret": {
       "value": "xxxxxxxxxxxxxxxxxxxxx",
       "sensitive": true
     },
     "cognito_domain": {
       "value": "balansi-dev-xxxxx.auth.sa-east-1.amazoncognito.com"
     },
     "database_url": {
       "value": "postgresql://balansi_dev_user:password@localhost:5432/balansi_dev",
       "sensitive": true
     },
     "database_name": {
       "value": "balansi_dev"
     },
     "database_user": {
       "value": "balansi_dev_user"
     }
   }
   ```

**For Staging/Production (Shared RDS):**

First, create the shared RDS instance:
```bash
cd terraform/environments/shared
terraform init
terraform apply
```

Then get outputs for staging/production:
```json
{
  "rds_endpoint": {
    "value": "balansi-shared.xxxxxxxxxxxx.sa-east-1.rds.amazonaws.com"
  },
  "rds_port": {
    "value": 5432
  },
  "staging_database_url": {
    "value": "postgresql://balansi_staging_user:password@balansi-shared.xxxxxxxxxxxx.sa-east-1.rds.amazonaws.com:5432/balansi_staging",
    "sensitive": true
  },
  "production_database_url": {
    "value": "postgresql://balansi_production_user:password@balansi-shared.xxxxxxxxxxxx.sa-east-1.rds.amazonaws.com:5432/balansi_production",
    "sensitive": true
  }
}
```

**Example Terraform outputs configuration:**

```hcl
# terraform/modules/cognito/outputs.tf
output "user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.main.id
}

output "client_id" {
  description = "Cognito User Pool Client ID"
  value       = aws_cognito_user_pool_client.main.id
}

output "client_secret" {
  description = "Cognito User Pool Client Secret"
  value       = aws_cognito_user_pool_client.main.client_secret
  sensitive   = true
}

output "domain" {
  description = "Cognito User Pool Domain"
  value       = aws_cognito_user_pool_domain.main.domain
}
```

### 12.4 Master Key Management

**Development:**
- `config/master.key` stored locally (in `.gitignore`)
- Each developer has their own copy
- Can be shared via secure channel (1Password, etc.) if needed

**Staging/Production:**
- `RAILS_MASTER_KEY` environment variable set in CI/CD or deployment platform
- Or stored in AWS Secrets Manager and injected at runtime
- Never commit `master.key` to version control

**Kamal Integration:**
```yaml
# config/deploy.yml
env:
  secret:
    - RAILS_MASTER_KEY  # Set in .kamal/secrets or CI/CD
```

### 12.5 Benefits of Using Credentials

1. **No External Dependencies**: Uses Rails built-in encryption, no need for gems like `dotenv`
2. **Version Controlled**: Encrypted credentials file can be safely committed to Git
3. **Environment-Specific**: Separate credential files per environment
4. **Secure**: Master key never committed, secrets encrypted at rest
5. **Terraform Integration**: Easy to populate from Terraform outputs
6. **CI/CD Friendly**: Master key can be injected via environment variable

**Infrastructure Requirements:**
- **Cognito Region**: Must be in `sa-east-1` (São Paulo, Brazil) to minimize network latency for Brazilian users
- **Rails Application**: Must be hosted in `sa-east-1` (São Paulo, Brazil) region
- **Database**: Must be hosted in `sa-east-1` (São Paulo, Brazil) region for optimal performance
- **Language Detection**: Browser language is detected from Accept-Language header (pt-BR or en), defaults to pt-BR
- **Infrastructure as Code**: All infrastructure must be managed using Terraform with separate configurations for development, staging, and production environments
- **Development Cognito**: Use real AWS Cognito in development (not local/mock) - created via Terraform

---

## 13. Security Considerations

### 13.1 Session Security

- **Session Storage**: Rails session stored in httpOnly cookies (prevents XSS)
- **Cookie Security**: Secure flag enabled in production (HTTPS only)
- **SameSite**: Lax policy prevents CSRF attacks
- **Session Encryption**: Rails automatically encrypts session data
- **Session Expiration**: Managed by Rails (configurable in `config/session_store`), set to 30 days to align with Cognito refresh token validity
- **Session Data**: `session[:user_id]` and `session[:refresh_token]` are stored in the session cookie; `cognito_id` is stored in database and accessed via `current_user.cognito_id` when needed; `refresh_token` is stored for future token refresh functionality (not used in v1, but stored to avoid logout when implementing token refresh)

### 13.2 State Parameter and CSRF Protection

- **CSRF Token Generation**: Cryptographically secure token (32 bytes, base64url encoded) generated using `SecureRandom.urlsafe_base64(32)`
- **Token Storage**: Stored in `session[:oauth_state]` for validation on callback
- **State Format**: `csrf_token=XXX&professional_id=YYY` (URL-encoded)
- **Validation**: State parameter validated in callback using constant-time comparison (`ActiveSupport::SecurityUtils.secure_compare`) to prevent timing attacks
- **One-Time Use**: CSRF token is cleared from session after successful validation (prevents reuse)
- **Business Parameters**: Only after CSRF validation, business parameters (e.g., professional_id) are extracted from state
- **Encoding**: URL-encode state parameter before sending to Cognito
- **Size Limit**: Cognito supports state up to 2048 characters

### 13.3 HTTPS

- **Production**: All endpoints must use HTTPS
- **Development**: Can use HTTP for localhost only
- **Session Cookie**: Secure flag automatically set in production

### 13.4 CSRF Protection (Additional)

- **OAuth State Parameter**: CSRF protection via state parameter validation (see section 13.2)
- **Rails CSRF Token**: Automatically included in forms (for non-OAuth forms)
- **Verify Authenticity Token**: Enabled by default in Rails controllers
- **SameSite Cookie**: Provides additional CSRF protection
- **ID Token Verification**: JWT signature verification using Cognito JWKS prevents token tampering
- **Authorization Code Idempotency**: Codes can only be used once (cached for 5 minutes after processing)

### 13.5 Rate Limiting

**Implementation**: Uses `rack-attack` gem for rate limiting (disabled in test environment)

**Rate Limits:**
- `/auth/callback`: 5 requests per IP per minute + 30 requests per hour (strict limit to prevent arbitrary user creation)
- `/auth/sign_up`: 5 requests per IP per minute + 20 requests per hour (prevents abuse of registration flow)
- `/auth/sign_in`: 20 requests per IP per minute (prevents abuse of CSRF token generation)
- Generic rule: 300 requests per IP per minute for all other endpoints (prevents general DoS attacks)

**Features:**
- Custom 429 response with `Retry-After` and `RateLimit-*` headers
- Comprehensive logging for all throttled requests
- Health check endpoint (`/up`) excluded from rate limiting
- Static assets excluded from rate limiting (handled by web server/CDN in production)

---

## 14. Error Handling

### 14.1 Callback Errors

If callback fails:
- Log error details to Rails logger
- Redirect to home with error flash message
- User can retry authentication

### 14.2 Session Expiration

**Session Expiration Alignment:**
- Rails session expires after 30 days (configured in `config/application.rb` with `expire_after: 30.days`)
- Cognito refresh token expires after 30 days (configured in Terraform with `refresh_token_validity = 30`)
- Both are aligned to ensure consistent user experience
- Access token expires after 1 hour, but session remains valid for 30 days (refresh_token stored in session can be used to get new access tokens in future implementation)

**When session expires:**
- Rails `authenticate_user!` before_action detects expired session (after 30 days)
- User redirected to Cognito Hosted UI for re-authentication
- After re-authentication, callback recreates session with new tokens
- Session expiration is automatic - no manual cleanup needed

**Token Expiration Behavior:**
- **Access Token**: Expires after 1 hour (short-lived for security)
- **Refresh Token**: Expires after 30 days (stored in session for future use)
- **Session**: Expires after 30 days (aligned with refresh_token_validity)
- **In v1**: User must re-authenticate after 30 days (refresh token functionality not implemented yet)

### 14.3 Authentication Errors

If authentication fails:
- `authenticate_user!` redirects to Cognito login
- Flash messages can be used to inform user
- All errors logged for debugging

---

## 15. Testing

### 15.1 Unit Tests

**Testing Strategy:**
- All tests use mocks for Cognito API calls
- No real Cognito calls during tests
- Fast, isolated, and deterministic tests

**Test Coverage:**

**CognitoService Tests:**
- `exchange_code_for_tokens` - Mock HTTParty responses, error handling
- `get_user_info` - Mock HTTParty responses, error handling
- `decode_id_token` - JWT signature verification using JWKS (mock JWKS endpoint)
- `verify_id_token` - Token verification with valid/invalid tokens
- `validate_token_claims` - Audience and issuer validation
- `fetch_jwks` - JWKS fetching with caching
- `login_url` - URL generation with Managed Login V2 endpoint (/oauth2/authorize)
- `signup_url` - URL generation with Managed Login V2 endpoint (/oauth2/authorize)
- `logout_url` - URL generation with logout_uri normalization
- `cognito_language_code` - Locale to language code conversion
- `credentials` - Lazy credential loading, environment-specific credentials

**Auth::SignUpInteraction Tests:**
- User creation with valid Cognito response (mocked)
- User lookup for existing users (by cognito_id)
- Patient record creation with professional_id (required)
- Patient record creation failure when professional_id missing
- Professional ID parsing from state parameter
- Timezone and language detection (defaults)
- Token validation (all required tokens present)
- ID token verification (with mocked JWKS)
- User info extraction from ID token (preferred)
- User info fallback to userinfo endpoint
- Error handling for invalid tokens, expired tokens, missing tokens
- Error handling for token exchange failures (invalid_grant, etc.)
- Consistent error handling pattern (errors added to errors object)

**Auth::CallbacksController Tests:**
- CSRF protection validation (valid/invalid CSRF tokens)
- CSRF token constant-time comparison (prevents timing attacks)
- Authorization code idempotency check
- State parameter extraction (removes CSRF token, keeps business params)
- Successful authentication flow
- Error handling for invalid codes, token exchange failures
- Error message formatting (generic in production, detailed in development)
- Code marking as processed (idempotency)

**Auth::SessionsController Tests:**
- CSRF token generation (secure random, proper format)
- State parameter building (with/without professional_id)
- Redirect to appropriate Cognito endpoint (signup vs login)
- Managed Login V2 endpoint usage (/oauth2/authorize)
- Missing credentials error handling

**BrowserLanguage Concern Tests:**
- `detect_browser_language` - Accept-Language header parsing
- `set_locale` - Locale setting based on browser language
- Default to :pt for unknown languages

**BrowserTimezone Concern Tests:**
- `detect_browser_timezone` - Cookie reading
- Default to 'America/Sao_Paulo' if cookie not present

**User Model Tests:**
- Timezone validation using TZInfo (valid/invalid IANA timezone identifiers)
- Language validation (valid/invalid languages from i18n config)
- Associations (patients with dependent: :destroy)
- Default values (timezone: 'America/Sao_Paulo', language: 'pt')

**Patient Model Tests:**
- Unique constraint validation (user_id + professional_id)
- Associations (user)

**Example Test Structure:**

```ruby
# spec/services/cognito_service_spec.rb
RSpec.describe CognitoService do
  describe ".exchange_code_for_tokens" do
    it "exchanges code for tokens" do
      # Mock HTTParty response
      allow(HTTParty).to receive(:post).and_return(
        double(body: {
          "access_token" => "mock_access_token",
          "refresh_token" => "mock_refresh_token"
        }.to_json)
      )

      result = CognitoService.exchange_code_for_tokens("auth_code")
      expect(result["access_token"]).to eq("mock_access_token")
    end
  end
end

# spec/interactions/auth/sign_up_interaction_spec.rb
RSpec.describe Auth::SignUpInteraction do
  describe ".run" do
    it "creates user and patient record" do
      # Mock CognitoService calls
      allow(CognitoService).to receive(:exchange_code_for_tokens).and_return({
        "access_token" => "mock_token",
        "refresh_token" => "mock_refresh"
      })
      allow(CognitoService).to receive(:get_user_info).and_return({
        "sub" => "cognito_id_123",
        "name" => "Test User",
        "email" => "test@example.com"
      })

      result = Auth::SignUpInteraction.run(
        code: "auth_code",
        state: "professional_id=1",
        timezone: "America/Sao_Paulo",
        language: "pt"
      )

      expect(result.valid?).to be true
      expect(result.user).to be_persisted
      expect(result.user.email).to eq("test@example.com")
    end
  end
end
```

---

## 16. Summary

**Key Simplifications:**
- ✅ No custom auth forms (uses Cognito Hosted UI 100%)
- ✅ Single callback endpoint handles all post-authentication logic
- ✅ Rails native session management (no JWT tokens in frontend)
- ✅ Automatic creation of User and Patient records during callback
- ✅ Simplified architecture using Rails conventions
- ✅ Minimal implementation leveraging Cognito features

**Security Enhancements:**
- ✅ CSRF protection via state parameter validation with constant-time comparison
- ✅ Authorization code idempotency (prevents replay attacks)
- ✅ ID token signature verification using Cognito JWKS (with caching)
- ✅ Comprehensive rate limiting via rack-attack
- ✅ Session fixation prevention (reset_session after authentication)
- ✅ Generic error messages in production (no information leakage)

**Benefits:**
- Less code to maintain (Rails handles sessions, Cognito handles auth)
- Secure, compliant authentication forms (handled by Cognito)
- Password policy handled by Cognito
- Reduced attack surface (no custom auth forms, no JWT in frontend)
- Native Rails session security (httpOnly, Secure, SameSite)
- Onboarding can be implemented later without blocking authentication
- Low latency for Brazilian users (all infrastructure in sa-east-1 region)
- Native Portuguese language experience (pt-BR default)

---

## 17. Implementation Plan

**Issue**: [BAL-11 - Authentication using Cognito](https://linear.app/balansi/issue/BAL-11/authentication-using-cognito)

**Implementation Strategy**: Single PR with 3 sequential steps

**Step 1: Infrastructure Setup**
- Create Terraform configuration for AWS Cognito (development environment)
- Provision Cognito User Pool and Client via Terraform
- Configure Rails credentials with Cognito outputs (User Pool ID, Client ID, Domain, Region)
- Create README documenting Terraform setup and credentials configuration
- ✅ **Checkpoint: Review Step 1** before proceeding to Step 2

**Step 2: Core Implementation**
- Create database migrations (users table with cognito_id, timezone, language; patients table with unique constraint)
- Create Rails models (User, Patient) with validations
- Create CognitoService (login_url, signup_url, logout_url, exchange_code_for_tokens, get_user_info, cognito_language_code)
- Create Auth::SignUpInteraction (active_interaction gem)
- Create controllers (Auth::SessionsController, Auth::CallbacksController)
- Create ApplicationController helpers (authenticate_user!, current_user, detect_browser_language)
- Configure Rails session (expire_after: 30.days)
- Manual testing of complete authentication flow (signup, login, callback, session)
- ✅ **Checkpoint: Review Step 2** before proceeding to Step 3

**Step 3: Testing**
- Unit tests for CognitoService (with mocks)
- Unit tests for Auth::SignUpInteraction (with mocks)
- Unit tests for ApplicationController helpers
- Unit tests for User and Patient models
- ✅ **Checkpoint: Review Step 3** before opening PR

**Note**: This is a single PR implementation. All steps are completed sequentially with review checkpoints before proceeding to the next step.

---


**Document Version**: 3.1
**Last Updated**: 2026-01-10
**Status**: Updated to reflect current implementation

**Key Updates in v3.1:**
- Updated User model validation to use TZInfo for IANA timezone validation
- Updated authentication flows to include CSRF protection via state parameter
- Updated SignUpInteraction to use ID token verification with JWKS
- Updated CallbacksController to include CSRF validation and idempotency checks
- Updated SessionsController to generate CSRF tokens
- Updated CognitoService to use lazy credential loading and Managed Login V2 endpoints
- Updated ApplicationController to use concerns (BrowserLanguage, BrowserTimezone)
- Updated routes to use snake_case (/auth/sign_up, /auth/sign_in)
- Updated error handling to be more comprehensive
- Removed fallback to Professional.first (professional_id is now required)
