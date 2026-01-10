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
- `professional_id` comes from `state` parameter in Cognito callback
- If `professional_id` is missing, use first professional from database (temporary - onboarding screen to be implemented later)
- Both User and Patient records are created automatically during callback (onboarding flow to be implemented in the future)
- One user can have multiple patient records (one per professional)

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
- If `professional_id` is missing from state, use first professional from database (temporary solution)
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
  validates :timezone, presence: true, inclusion: { in: -> { User.valid_timezones } }
  validates :language, presence: true, inclusion: { in: -> { User.valid_languages } }

  # Get list of valid timezones from ActiveSupport::TimeZone
  def self.valid_timezones
    ActiveSupport::TimeZone.all.map(&:name)
  end

  # Get list of valid languages from Rails i18n configuration
  def self.valid_languages
    Rails.application.config.i18n.available_locales.map(&:to_s)
  end
end
```

**Validations:**
- **timezone**: Must be present and must be a valid timezone from `ActiveSupport::TimeZone.all`
- **language**: Must be present and must be one of the available locales configured in Rails (`config.i18n.available_locales`)

**Notes:**
- Timezone validation uses Rails' built-in timezone list (`ActiveSupport::TimeZone.all`)
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
1. User navigates to /auth/sign-up?professional_id=XX
   ↓
2. Rails redirects to Cognito Hosted UI:
   https://{domain}.auth.{region}.amazoncognito.com/signup?
     client_id={CLIENT_ID}&
     response_type=code&
     redirect_uri={CALLBACK_URI}&
     state=professional_id%3DXX&
     lang=pt-BR
   ↓
3. User completes signup in Cognito Hosted UI
   - Enters name, email, password (all handled by Cognito)
   - Cognito validates password policy
   - Cognito sends confirmation email
   ↓
4. User confirms email in Cognito Hosted UI (handled by Cognito)
   ↓
5. Cognito redirects to callback:
   https://app.balansi.me/auth/callback?
     code={AUTHORIZATION_CODE}&
     state=professional_id%3DXX
   ↓
6. Rails callback endpoint:
   - Exchanges code for tokens using Cognito
   - Gets user info from Cognito
   - Creates user record in database (if doesn't exist)
   - Creates patient record (user_id, professional_id) automatically
   - Creates Rails session with httpOnly cookie
   - Redirects to home (onboarding to be implemented later)
```

### 5.3 Sign In Flow (Existing User)

```
1. User navigates to protected route or clicks login link
   ↓
2. Rails checks for valid session (httpOnly cookie)
   ↓
3. If no valid session, redirects to Cognito Hosted UI:
   https://{domain}.auth.{region}.amazoncognito.com/login?
     client_id={CLIENT_ID}&
     response_type=code&
     redirect_uri={CALLBACK_URI}&
     state=professional_id%3DXX (optional)&
     lang=pt-BR
   ↓
4. User enters email/password in Cognito Hosted UI (handled by Cognito)
   ↓
5. Cognito validates credentials
   ↓
6. Cognito redirects to callback:
   https://app.balansi.me/auth/callback?
     code={AUTHORIZATION_CODE}&
     state=professional_id%3DXX
   ↓
7. Rails callback endpoint:
   - Exchanges code for tokens using Cognito
   - Gets user info from Cognito
   - Finds or creates user record
   - Creates patient record if professional_id in state (or uses first professional)
   - Creates Rails session with httpOnly cookie
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
1. Extract `code` and `state` from query parameters
2. Parse `state` to get `professional_id`:
   ```ruby
   state_params = URI.decode_www_form(state || "").to_h
   professional_id = state_params["professional_id"]
   ```
3. Exchange `code` for tokens using CognitoService:
   ```ruby
   # Use CognitoService to exchange authorization code for tokens
   tokens = CognitoService.exchange_code_for_tokens(code)
   access_token = tokens["access_token"]
   refresh_token = tokens["refresh_token"]
   ```
4. Get user info from Cognito using CognitoService:
   ```ruby
   # Use CognitoService to get user information from Cognito
   user_info = CognitoService.get_user_info(access_token)
   # user_info contains: sub, email, name, etc.
   ```
5. Find or create user record:
   ```ruby
   # Detect timezone and language from browser (only for new users)
   timezone = detect_browser_timezone
   language = detect_browser_language

   user = User.find_or_initialize_by(cognito_id: user_info["sub"])
   if user.new_record?
     user.name = user_info["name"]
     user.email = user_info["email"]
     user.timezone = timezone
     user.language = language
     user.save!
   end
   # Note: timezone and language are only set during initial user creation
   # Users can update these values manually later if needed
   ```
6. Create patient record (automatically):
   ```ruby
   # Get professional_id from state or use first professional
   professional_id = professional_id || Professional.first&.id

   # Create patient record if it doesn't exist
   patient = Patient.find_or_create_by!(
     user_id: user.id,
     professional_id: professional_id
   )
   ```
7. Create Rails session:
   ```ruby
   session[:user_id] = user.id
   session[:refresh_token] = refresh_token
   # Store user_id and refresh_token in session
   # user_id: used to identify current user
   # refresh_token: stored for future token refresh functionality (not used in v1, but stored to avoid logout when implementing token refresh)
   # cognito_id can be accessed via current_user.cognito_id when needed
   # Session cookie is automatically httpOnly, Secure, SameSite
   ```
8. Redirect to home:
   ```ruby
   redirect_to root_path
   ```

**Response**: Redirect to home page

**Error Handling:**
- Invalid `code`: Redirect to login with error message
- Token exchange failure: Redirect to login with error message
- User creation failure: Log error, redirect to login

### 6.2 Sign Out Endpoint

**Route**: `DELETE /auth/sign_out` or `GET /auth/sign_out`

**Controller**: `Auth::SessionsController#destroy`

**Purpose**: Sign out user by clearing Rails session and redirecting to Cognito logout.

**Processing:**
1. Clear Rails session:
   ```ruby
   reset_session
   ```
2. Redirect to Cognito logout URL (optional, to sign out from Cognito as well):
   ```ruby
   # Use CognitoService to generate logout URL
   redirect_to CognitoService.logout_url
   ```

### 6.3 Current User Helper

**Method**: `current_user` (ApplicationController concern)

**Purpose**: Get current authenticated user from session.

**Implementation:**
```ruby
module CurrentUser
  extend ActiveSupport::Concern

  included do
    helper_method :current_user
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
  include CurrentUser

  before_action :authenticate_user!
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
  httponly: true,
  secure: Rails.env.production?,
  same_site: :lax,
  expire_after: 30.days  # Align with Cognito refresh_token_validity (30 days)
```

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
  include CurrentUser

  before_action :authenticate_user!
  before_action :set_locale

  helper_method :detect_browser_language, :detect_browser_timezone

  private

  # Detect browser language from Accept-Language header
  # Returns locale symbol (:pt or :en), defaults to :pt
  def detect_browser_language
    accept_language = request.headers["Accept-Language"]
    return :pt if accept_language.blank?

    # Parse Accept-Language header (e.g., "pt-BR,pt;q=0.9,en;q=0.8")
    languages = accept_language.split(",").map do |lang|
      lang.split(";").first.strip.downcase
    end

    # Check for pt-BR or pt first
    return :pt if languages.any? { |l| l.start_with?("pt") }

    # Check for en
    return :en if languages.any? { |l| l.start_with?("en") }

    # Default to pt if not pt or en
    :pt
  end

  # Detect browser timezone from cookies
  # Returns timezone string (e.g., 'America/Sao_Paulo'), defaults to 'America/Sao_Paulo'
  def detect_browser_timezone
    # Check for timezone in cookies (set by JavaScript)
    timezone = cookies[:timezone]
    return timezone if timezone.present?

    # Fallback to default Brazilian timezone
    "America/Sao_Paulo"
  end

  # Set Rails locale based on browser language
  def set_locale
    locale = detect_browser_language
    I18n.locale = locale || I18n.default_locale
  end
end
```

### 7.3 Route Protection

**File**: `config/routes.rb`

```ruby
Rails.application.routes.draw do
  # Auth routes
  get "/auth/callback", to: "auth/callbacks#show"
  get "/auth/sign_up", to: "auth/sessions#new"
  get "/auth/sign_in", to: "auth/sessions#new"
  delete "/auth/sign_out", to: "auth/sessions#destroy"

  # Protected routes
  resources :meals
  resources :patients
  # ... other protected resources

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
  COGNITO_DOMAIN = Rails.application.credentials.cognito[:domain]
  COGNITO_REGION = Rails.application.credentials.cognito[:region]
  CLIENT_ID = Rails.application.credentials.cognito[:client_id]
  CLIENT_SECRET = Rails.application.credentials.cognito[:client_secret]
  REDIRECT_URI = Rails.application.credentials.cognito[:redirect_uri]
  LOGOUT_URI = Rails.application.credentials.cognito[:logout_uri] rescue nil

  def self.exchange_code_for_tokens(code)
    response = HTTParty.post(token_url, body: {
      grant_type: "authorization_code",
      code: code,
      client_id: CLIENT_ID,
      client_secret: CLIENT_SECRET,
      redirect_uri: REDIRECT_URI
    })
    JSON.parse(response.body)
  end

  def self.get_user_info(access_token)
    response = HTTParty.get(userinfo_url, headers: {
      "Authorization" => "Bearer #{access_token}"
    })
    JSON.parse(response.body)
  end

  def self.login_url(state: nil, locale: :pt)
    lang = cognito_language_code(locale)
    params = {
      client_id: CLIENT_ID,
      response_type: "code",
      redirect_uri: REDIRECT_URI,
      scope: "openid email profile",
      lang: lang
    }
    params[:state] = state if state
    "#{base_url}/login?#{params.to_query}"
  end

  def self.signup_url(state: nil, locale: :pt)
    lang = cognito_language_code(locale)
    params = {
      client_id: CLIENT_ID,
      response_type: "code",
      redirect_uri: REDIRECT_URI,
      scope: "openid email profile",
      lang: lang
    }
    params[:state] = state if state
    "#{base_url}/signup?#{params.to_query}"
  end

  def self.logout_url(logout_uri: nil)
    # Use provided logout_uri, or from credentials, or fallback to redirect_uri
    logout_uri ||= LOGOUT_URI || REDIRECT_URI
    params = {
      client_id: CLIENT_ID,
      logout_uri: logout_uri
    }
    "#{base_url}/logout?#{params.to_query}"
  end

  # Convert browser language locale to Cognito language code
  # Returns "pt-BR" or "en", defaults to "pt-BR"
  # @param locale [Symbol] Browser locale (:pt or :en)
  # @return [String] Cognito language code ("pt-BR" or "en")
  def self.cognito_language_code(locale)
    case locale
    when :pt
      "pt-BR"
    when :en
      "en"
    else
      "pt-BR"
    end
  end

  private

  def self.base_url
    "https://#{COGNITO_DOMAIN}.auth.#{COGNITO_REGION}.amazoncognito.com"
  end

  def self.token_url
    "#{base_url}/oauth2/token"
  end

  def self.userinfo_url
    "#{base_url}/oauth2/userInfo"
  end
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
    professional_id = params[:professional_id]
    state = professional_id ? "professional_id=#{professional_id}" : nil
    redirect_to CognitoService.signup_url(state: state, locale: detect_browser_language)
  end

  def destroy
    reset_session
    # Optionally redirect to Cognito logout to sign out from Cognito as well:
    # redirect_to CognitoService.logout_url
    # Or redirect to home:
    redirect_to root_path
  end
end
```

### 10.2 Callback Controller

**File**: `app/controllers/auth/callbacks_controller.rb`

```ruby
class Auth::CallbacksController < ApplicationController
  skip_before_action :authenticate_user!

  def show
    result = Auth::SignUpInteraction.run(
      code: params[:code],
      state: params[:state],
      timezone: detect_browser_timezone,
      language: detect_browser_language.to_s
    )

    if result.valid?
      session[:user_id] = result.user.id
      session[:refresh_token] = result.refresh_token
      redirect_to root_path
    else
      Rails.logger.error("Auth callback error: #{result.errors.full_messages.join(', ')}")
      redirect_to root_path, alert: "Authentication failed"
    end
  rescue => e
    Rails.logger.error("Auth callback error: #{e.message}")
    redirect_to root_path, alert: "Authentication failed"
  end
end
```

**Notes:**
- Controller is thin - business logic is delegated to `Auth::SignUpInteraction`
- Error handling is simplified - the interaction handles all validations and errors
- Session creation is done in the controller after successful interaction

### 10.3 Sign Up Interaction

**File**: `app/interactions/auth/sign_up_interaction.rb`

**Gem**: `active_interaction` - Add to `Gemfile`:
```ruby
gem 'active_interaction', '~> 5.0'
```

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
      # Exchange code for tokens
      tokens = CognitoService.exchange_code_for_tokens(code)
      access_token = tokens["access_token"]
      refresh_token = tokens["refresh_token"]

      # Get user info from Cognito
      user_info = CognitoService.get_user_info(access_token)

      # Detect timezone and language from browser (only for new users)
      detected_timezone = timezone || "America/Sao_Paulo"
      detected_language = language || "pt"

      # Find or create user
      user = find_or_create_user(user_info, detected_timezone, detected_language)

      # Parse state to get professional_id
      professional_id = parse_professional_id

      # Create patient record automatically
      create_patient_record(user, professional_id)

      # Return user and refresh_token as result attributes
      # ActiveInteraction automatically makes these available on the result object
      { user: user, refresh_token: refresh_token }
    end

    private

    def find_or_create_user(user_info, detected_timezone, detected_language)
      user = User.find_or_initialize_by(cognito_id: user_info["sub"])
      
      if user.new_record?
        user.name = user_info["name"]
        user.email = user_info["email"]
        user.timezone = detected_timezone
        user.language = detected_language
        user.save!
      end
      # Note: timezone and language are only set during initial user creation
      # Users can update these values manually later if needed

      user
    end

    def parse_professional_id
      return nil if state.blank?
      URI.decode_www_form(state).to_h["professional_id"]
    end

    def create_patient_record(user, professional_id)
      professional_id ||= Professional.first&.id
      return unless professional_id

      Patient.find_or_create_by!(
        user_id: user.id,
        professional_id: professional_id
      )
    end
  end
end
```

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

### 11.2 Hosted UI Domain

**Configured via Terraform:**
- Custom domain: `auth.balansi.me` (production)
- Or use Cognito default: `{pool-name}.auth.{region}.amazoncognito.com` (development)
- Domain configuration is managed in Terraform module

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
# In config/application.rb or config/environments/*.rb
Rails.application.credentials.cognito[:user_pool_id]
Rails.application.credentials.cognito[:client_id]
Rails.application.credentials.cognito[:client_secret]
Rails.application.credentials.cognito[:domain]
Rails.application.credentials.cognito[:region]
Rails.application.credentials.database[:url]
```

**Update CognitoService to use credentials:**

```ruby
# app/services/cognito_service.rb
class CognitoService
  COGNITO_DOMAIN = Rails.application.credentials.cognito[:domain]
  COGNITO_REGION = Rails.application.credentials.cognito[:region]
  CLIENT_ID = Rails.application.credentials.cognito[:client_id]
  CLIENT_SECRET = Rails.application.credentials.cognito[:client_secret]
  REDIRECT_URI = Rails.application.credentials.cognito[:redirect_uri]

  # ... rest of the service
end
```

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

### 13.2 State Parameter

- **Encoding**: URL-encode state parameter before sending to Cognito
- **Validation**: Validate state parameter in callback (prevent CSRF)
- **Size Limit**: Cognito supports state up to 2048 characters

### 13.3 HTTPS

- **Production**: All endpoints must use HTTPS
- **Development**: Can use HTTP for localhost only
- **Session Cookie**: Secure flag automatically set in production

### 13.4 CSRF Protection

- **Rails CSRF Token**: Automatically included in forms
- **Verify Authenticity Token**: Enabled by default in Rails controllers
- **SameSite Cookie**: Provides additional CSRF protection

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
- `exchange_code_for_tokens` - Mock HTTParty responses
- `get_user_info` - Mock HTTParty responses
- `login_url` - URL generation with locale conversion
- `signup_url` - URL generation with locale conversion
- `logout_url` - URL generation
- `cognito_language_code` - Locale to language code conversion

**Auth::SignUpInteraction Tests:**
- User creation with valid Cognito response (mocked)
- User lookup for existing users
- Patient record creation
- Professional ID parsing from state
- Timezone and language detection
- Error handling for invalid tokens

**ApplicationController Tests:**
- `detect_browser_language` - Accept-Language header parsing
- `detect_browser_timezone` - Cookie reading
- `set_locale` - Locale setting based on browser language

**User Model Tests:**
- Timezone validation (valid/invalid timezones)
- Language validation (valid/invalid languages)
- Associations (patients)

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

## 17. Summary

**Key Simplifications:**
- ✅ No custom auth forms (uses Cognito Hosted UI 100%)
- ✅ Single callback endpoint handles all post-authentication logic
- ✅ Rails native session management (no JWT tokens in frontend)
- ✅ Automatic creation of User and Patient records during callback
- ✅ Simplified architecture using Rails conventions
- ✅ Minimal implementation leveraging Cognito features

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


**Document Version**: 3.0
**Last Updated**: 2026 Jan
**Status**: Draft - Pending Review
