# Entity Relationship Diagram — Authentication (Balansi)

## 1. Architecture Overview

The Authentication module provides secure user registration and login for the Balansi platform using **AWS Cognito Hosted UI**. This simplified architecture eliminates the need for custom authentication forms in the frontend.

**Key Components:**
- **Frontend**: SvelteKit web application (no auth pages - uses Cognito Hosted UI)
- **Backend API**: Elixir/Phoenix service (handles callback and token validation)
- **Identity Provider**: AWS Cognito Hosted UI (handles all login/signup forms)
- **Database**: PostgreSQL (user records, patient records)
- **Token Storage**: Access tokens in memory (Svelte), refresh tokens via Cognito

**Key Design Decisions:**
- **Cognito Hosted UI**: All authentication forms (signup, login, password recovery) are handled by Cognito
- **No Custom Auth Pages**: Frontend redirects to Cognito Hosted UI instead of showing custom forms
- **Callback Endpoint**: Single endpoint (`/auth/callback`) handles post-authentication processing
- **Token Validation**: JWT tokens validated using Cognito JWKS endpoint
- **Refresh Token**: Automatic token refresh in Svelte using Cognito token endpoint

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
| `created_at` | TIMESTAMP(0) | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Record creation timestamp |
| `updated_at` | TIMESTAMP(0) | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Record last update timestamp |

**Indexes:**
- Primary Key: `users_pkey` on `id`
- Unique Index: `users_email_key` on `email`
- Unique Index: `users_cognito_id_key` on `cognito_id`

**Notes:**
- `cognito_id` is set during callback processing (after Cognito authentication)
- `name` and `email` are extracted from Cognito user attributes
- No `status` field needed - Cognito handles email confirmation

#### Patient

The `patients` table links users to professionals (nutritionists). Created during the authentication callback.

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
- If `professional_id` is missing, use first professional from database (temporary - will add selection screen later)
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
- **created_at**: Timestamp when user record was created
- **updated_at**: Timestamp when user record was last modified

**Changes from Previous Version:**
- Removed `temporary_password` field (not needed with Cognito Hosted UI)
- Removed `status` field (Cognito handles email confirmation)
- Made `cognito_id` NOT NULL (always set during callback)

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

---

## 4. Authentication Flow

### 4.1 Overview

The authentication flow uses **Cognito Hosted UI** for all user-facing authentication forms. The frontend redirects users to Cognito, and Cognito redirects back to a callback endpoint after authentication.

### 4.2 Sign Up Flow (New User)

```
1. User clicks link: /auth/sign-up?professional_id=XX
   ↓
2. Frontend redirects to Cognito Hosted UI:
   https://{domain}.auth.{region}.amazoncognito.com/login?
     client_id={CLIENT_ID}&
     response_type=code&
     redirect_uri={CALLBACK_URI}&
     state=professional_id%3DXX
   ↓
3. User completes signup in Cognito Hosted UI
   - Enters name, email, password
   - Cognito validates password policy
   - Cognito sends confirmation email
   ↓
4. User confirms email in Cognito Hosted UI
   ↓
5. Cognito redirects to callback:
   https://app.balansi.me/auth/callback?
     code={AUTHORIZATION_CODE}&
     state=professional_id%3DXX
   ↓
6. Backend callback endpoint:
   - Exchanges code for tokens
   - Gets user info from Cognito
   - Creates user record in database
   - Creates patient record (user_id, professional_id)
   - Sets session cookie (if using session-based auth)
   - Redirects to onboarding or home
```

### 4.3 Sign In Flow (Existing User)

```
1. User navigates to protected route or clicks login link
   ↓
2. Frontend checks for valid access token
   ↓
3. If no valid token, redirects to Cognito Hosted UI:
   https://{domain}.auth.{region}.amazoncognito.com/login?
     client_id={CLIENT_ID}&
     response_type=code&
     redirect_uri={CALLBACK_URI}&
     state=professional_id%3DXX (optional)
   ↓
4. User enters email/password in Cognito Hosted UI
   ↓
5. Cognito validates credentials
   ↓
6. Cognito redirects to callback:
   https://app.balansi.me/auth/callback?
     code={AUTHORIZATION_CODE}&
     state=professional_id%3DXX
   ↓
7. Backend callback endpoint:
   - Exchanges code for tokens
   - Gets user info from Cognito
   - Finds or creates user record
   - Creates patient record if professional_id in state
   - Sets session cookie (if using session-based auth)
   - Redirects to home or onboarding
```

### 4.4 Password Recovery Flow

Password recovery is handled entirely by Cognito Hosted UI. Users click "Forgot Password" in the Cognito login form, and Cognito handles the entire flow (email verification, password reset).

---

## 5. API Endpoints

### 5.1 Callback Endpoint

**Endpoint**: `GET /auth/callback`

**Purpose**: Handles Cognito Hosted UI redirect after authentication.

**Query Parameters:**
- `code` (required): Authorization code from Cognito
- `state` (optional): State parameter containing `professional_id=XX`

**Processing Steps:**
1. Extract `code` and `state` from query parameters
2. Parse `state` to get `professional_id`:
   ```elixir
   state_params = URI.decode_query(state || "")
   professional_id = state_params["professional_id"]
   ```
3. Exchange `code` for tokens using Cognito Token endpoint:
   ```elixir
   # POST https://{domain}.auth.{region}.amazoncognito.com/oauth2/token
   # Body: grant_type=authorization_code&code={code}&client_id={CLIENT_ID}&redirect_uri={REDIRECT_URI}
   ```
4. Get user info from Cognito using access token:
   ```elixir
   # GET https://{domain}.auth.{region}.amazoncognito.com/oauth2/userInfo
   # Header: Authorization: Bearer {access_token}
   ```
5. Find or create user record:
   ```elixir
   user = Repo.get_by(User, cognito_id: cognito_user_sub)
   if !user do
     # Create new user
     user = %User{
       name: cognito_name,
       email: cognito_email,
       cognito_id: cognito_user_sub
     }
     |> Repo.insert!()
   end
   ```
6. Create patient record:
   ```elixir
   # Get professional_id from state or use first professional
   professional_id = professional_id || get_first_professional_id()

   # Check if patient record already exists
   patient = Repo.get_by(Patient, user_id: user.id, professional_id: professional_id)
   if !patient do
     patient = %Patient{
       user_id: user.id,
       professional_id: professional_id
     }
     |> Repo.insert!()
   end
   ```
7. Store tokens (options):
   - Option A: Set httpOnly cookie with refresh token
   - Option B: Return tokens to frontend (store access token in memory, refresh token in httpOnly cookie)
8. Redirect to frontend:
   ```elixir
   redirect(conn, external: "https://app.balansi.me/?token={access_token}")
   # OR set cookie and redirect to home
   ```

**Response**: Redirect to frontend (home page or onboarding)

**Error Handling:**
- Invalid `code`: Redirect to login with error message
- Token exchange failure: Redirect to login with error message
- User creation failure: Log error, redirect to login

### 5.2 Token Refresh Endpoint

**Endpoint**: `POST /auth/refresh`

**Purpose**: Refresh access token using refresh token from Cognito.

**Request**:
- Cookie: `refresh_token` (httpOnly cookie, if using cookie-based storage)
- OR Body: `{ "refresh_token": "..." }` (if using body-based storage)

**Processing:**
1. Extract refresh token from cookie or body
2. Call Cognito Token endpoint:
   ```elixir
   # POST https://{domain}.auth.{region}.amazoncognito.com/oauth2/token
   # Body: grant_type=refresh_token&refresh_token={refresh_token}&client_id={CLIENT_ID}
   ```
3. Return new access token:
   ```json
   {
     "accessToken": "eyJraWQiOiJ...",
     "expiresIn": 3600
   }
   ```

**Response** (200):
```json
{
  "accessToken": "eyJraWQiOiJ...",
  "expiresIn": 3600
}
```

**Error Codes**: `invalid_refresh_token` (401), `refresh_failed` (401)

### 5.3 User Info Endpoint

**Endpoint**: `GET /auth/me`

**Purpose**: Get current user information.

**Request**:
- Header: `Authorization: Bearer {access_token}`

**Processing:**
1. Validate JWT token (see section 6.1)
2. Extract `sub` (cognito_id) from token
3. Find user by `cognito_id`
4. Return user info

**Response** (200):
```json
{
  "id": 1,
  "name": "John Doe",
  "email": "john@example.com"
}
```

**Error Codes**: `unauthorized` (401), `invalid_token` (401), `user_not_found` (404)

---

## 6. Token Validation in Journal API

### 6.1 JWT Validation Plug

The Journal API validates JWT tokens from Cognito using a Plug that:
1. Extracts `Authorization: Bearer {token}` header
2. Validates token signature using Cognito JWKS endpoint
3. Verifies token expiration
4. Extracts `sub` (cognito_id) from token
5. Looks up user in database
6. Extracts `patient_id` from user's patient record
7. Adds `current_user` and `current_patient_id` to `conn.assigns`

**Implementation** (Elixir):

```elixir
defmodule JournalWeb.Plugs.VerifyToken do
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    case extract_token(conn) do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Missing authorization header"})
        |> halt()

      token ->
        case validate_token(token) do
          {:ok, cognito_id} ->
            case get_user_by_cognito_id(cognito_id) do
              nil ->
                conn
                |> put_status(:not_found)
                |> json(%{error: "User not found"})
                |> halt()

              user ->
                patient_id = get_patient_id(user.id)
                conn
                |> assign(:current_user, user)
                |> assign(:current_patient_id, patient_id)
            end

          {:error, reason} ->
            Logger.warn("Token validation failed: #{inspect(reason)}")
            conn
            |> put_status(:unauthorized)
            |> json(%{error: "Invalid token"})
            |> halt()
        end
    end
  end

  defp extract_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token
      _ -> nil
    end
  end

  defp validate_token(token) do
    # Use library like joken or jose to validate JWT
    # Fetch JWKS from Cognito: https://cognito-idp.{region}.amazonaws.com/{userPoolId}/.well-known/jwks.json
    # Verify signature and expiration
    # Return {:ok, cognito_id} or {:error, reason}
  end

  defp get_user_by_cognito_id(cognito_id) do
    Repo.get_by(User, cognito_id: cognito_id)
  end

  defp get_patient_id(user_id) do
    # Get first patient for user (or implement selection logic)
    patient = Repo.get_by(Patient, user_id: user_id)
    patient && patient.id
  end
end
```

**Usage in Router:**

```elixir
defmodule JournalWeb.Router do
  use JournalWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :protected do
    plug JournalWeb.Plugs.VerifyToken
  end

  scope "/journal", JournalWeb do
    pipe_through [:api, :protected]

    get "/meals", MealController, :index
    post "/meals", MealController, :create
    # ... other protected routes
  end
end
```

**Controller Usage:**

```elixir
defmodule JournalWeb.MealController do
  use JournalWeb, :controller

  def index(conn, _params) do
    patient_id = conn.assigns[:current_patient_id]
    meals = MealService.list_meals(patient_id)
    json(conn, %{data: meals})
  end
end
```

---

## 7. Refresh Token in Svelte Frontend

### 7.1 Token Storage

**Access Token**: Stored in memory (Svelte store or module variable)
- **Location**: `src/lib/auth/token.ts`
- **Storage**: In-memory variable (not localStorage)
- **Expiration**: Tracked with timestamp

**Refresh Token**: Stored in httpOnly cookie (set by backend)
- **Cookie Name**: `refresh_token` (or `session_id` if using encrypted session)
- **HttpOnly**: `true` (prevents JavaScript access)
- **Secure**: `true` (HTTPS only in production)
- **SameSite**: `Lax` or `None` (depending on cross-domain requirements)

### 7.2 Token Refresh Implementation

**File**: `src/lib/auth/token.ts`

```typescript
// In-memory access token storage
let accessToken: string | null = null;
let tokenExpiresAt: number | null = null; // Timestamp in milliseconds

// Token expiry buffer - refresh 5 minutes before expiration
const TOKEN_EXPIRY_BUFFER = 5 * 60 * 1000; // 5 minutes

/**
 * Get access token, refreshing if necessary
 */
export async function getAccessToken(): Promise<string | null> {
  // Check if we have a valid token
  if (accessToken && tokenExpiresAt && Date.now() < tokenExpiresAt - TOKEN_EXPIRY_BUFFER) {
    return accessToken;
  }

  // Token expired or missing - refresh it
  return await refreshAccessToken();
}

/**
 * Refresh access token using refresh token from cookie
 */
export async function refreshAccessToken(): Promise<string | null> {
  if (!browser) {
    return null; // Server-side rendering
  }

  try {
    const apiUrl = getApiBaseUrl();
    const response = await fetch(`${apiUrl}/auth/refresh`, {
      method: "POST",
      credentials: "include", // Include refresh_token cookie
    });

    if (response.ok) {
      const data = await response.json();

      if (data.accessToken && data.expiresIn) {
        setAccessToken(data.accessToken, data.expiresIn);
        return data.accessToken;
      }
    }

    // Refresh failed - clear token
    clearAccessToken();
    return null;
  } catch (error) {
    console.error("Error refreshing access token:", error);
    clearAccessToken();
    return null;
  }
}

/**
 * Set access token with expiration
 */
function setAccessToken(token: string, expiresIn: number) {
  accessToken = token;
  tokenExpiresAt = Date.now() + (expiresIn * 1000);
}

/**
 * Clear access token
 */
export function clearAccessToken() {
  accessToken = null;
  tokenExpiresAt = null;
}
```

### 7.3 Automatic Token Refresh in API Calls

**File**: `src/lib/api/wrapper.ts` (or similar)

```typescript
export async function authenticatedFetch(url: string, options: RequestInit = {}): Promise<Response> {
  // Get access token (will refresh if needed)
  const token = await getAccessToken();

  if (!token) {
    // No token - redirect to login
    window.location.href = getCognitoLoginUrl();
    throw new Error("Not authenticated");
  }

  const headers = new Headers(options.headers);
  headers.set("Authorization", `Bearer ${token}`);

  let response = await fetch(url, {
    ...options,
    headers,
    credentials: "include", // Include cookies
  });

  // If 401, try refreshing token once
  if (response.status === 401) {
    clearAccessToken();
    const newToken = await refreshAccessToken();

    if (newToken) {
      headers.set("Authorization", `Bearer ${newToken}`);
      response = await fetch(url, {
        ...options,
        headers,
        credentials: "include",
      });
    } else {
      // Refresh failed - redirect to login
      window.location.href = getCognitoLoginUrl();
      throw new Error("Authentication failed");
    }
  }

  return response;
}

function getCognitoLoginUrl(): string {
  const clientId = import.meta.env.VITE_COGNITO_CLIENT_ID;
  const domain = import.meta.env.VITE_COGNITO_DOMAIN;
  const redirectUri = encodeURIComponent(import.meta.env.VITE_COGNITO_REDIRECT_URI);

  return `https://${domain}.auth.${region}.amazoncognito.com/login?` +
    `client_id=${clientId}&` +
    `response_type=code&` +
    `redirect_uri=${redirectUri}`;
}
```

### 7.4 Route Protection

**File**: `src/routes/+layout.svelte` or `src/hooks.ts`

```typescript
import { getAccessToken } from "$lib/auth/token";
import { browser } from "$app/environment";

export async function load({ url }) {
  if (browser) {
    // Check if route requires authentication
    const isProtectedRoute = !url.pathname.startsWith("/auth/");

    if (isProtectedRoute) {
      const token = await getAccessToken();

      if (!token) {
        // Redirect to Cognito login
        const loginUrl = getCognitoLoginUrl();
        return {
          redirect: 302,
          location: loginUrl
        };
      }
    }
  }

  return {};
}
```

---

## 8. Frontend Changes

### 8.1 Removed Pages

The following pages should be **removed** from the frontend:

- `src/routes/auth/sign-up/+page.svelte` ❌
- `src/routes/auth/sign-in/+page.svelte` ❌
- `src/routes/auth/forgot-password/+page.svelte` ❌
- `src/routes/auth/reset-password/+page.svelte` ❌
- `src/routes/auth/confirmation/+page.svelte` ❌

### 8.2 New Redirect Logic

Instead of showing custom forms, the frontend should redirect to Cognito Hosted UI:

**File**: `src/lib/auth/cognito.ts`

```typescript
/**
 * Redirect to Cognito Hosted UI for signup
 */
export function redirectToSignup(professionalId?: string): void {
  const state = professionalId ? `professional_id=${professionalId}` : "";
  const url = getCognitoAuthUrl("signup", state);
  window.location.href = url;
}

/**
 * Redirect to Cognito Hosted UI for login
 */
export function redirectToLogin(professionalId?: string): void {
  const state = professionalId ? `professional_id=${professionalId}` : "";
  const url = getCognitoAuthUrl("login", state);
  window.location.href = url;
}

function getCognitoAuthUrl(action: "signup" | "login", state: string): string {
  const clientId = import.meta.env.VITE_COGNITO_CLIENT_ID;
  const domain = import.meta.env.VITE_COGNITO_DOMAIN;
  const region = import.meta.env.VITE_COGNITO_REGION;
  const redirectUri = encodeURIComponent(import.meta.env.VITE_COGNITO_REDIRECT_URI);

  const baseUrl = `https://${domain}.auth.${region}.amazoncognito.com/${action}?`;
  const params = new URLSearchParams({
    client_id: clientId,
    response_type: "code",
    redirect_uri: redirectUri,
    scope: "openid email profile", // IMPORTANT: Include 'profile' scope to get 'name' and 'preferred_username'
    ...(state && { state })
  });

  return baseUrl + params.toString();
}
```

### 8.3 Callback Page

**File**: `src/routes/auth/callback/+page.svelte` (optional - backend can handle redirect)

If the backend redirects to frontend after processing callback, this page can:
- Extract token from URL (if passed)
- Store token in memory
- Redirect to home or onboarding

---

## 9. Cognito Configuration

### 9.1 User Pool Client Settings

**Allowed OAuth Flows:**
- Authorization code grant
- Implicit grant (optional)

**Allowed OAuth Scopes:**
- `openid`
- `email`
- `profile`

**Allowed Callback URLs:**
- `https://app.balansi.me/auth/callback` (production)
- `http://localhost:5173/auth/callback` (development)

**Allowed Sign-out URLs:**
- `https://app.balansi.me/` (production)
- `http://localhost:5173/` (development)

### 9.2 Hosted UI Domain

Configure a custom domain for Cognito Hosted UI:
- Example: `auth.balansi.me`
- Or use Cognito default: `{pool-name}.auth.{region}.amazoncognito.com`

### 9.3 Configuring Sign-up Form Fields (Including "name")

To include the "name" field in the Cognito Hosted UI sign-up form, you need to:

#### Option 1: Via AWS Console (Recommended for Production)

1. **Go to Cognito User Pool → Sign-up experience**:
   - Navigate to AWS Console → Cognito → Your User Pool
   - Click on "Sign-up experience" tab
   - Under "Required attributes", ensure "name" is checked
   - OR under "Optional attributes", ensure "name" is available

2. **Configure Attribute Settings**:
   - Go to "Attributes" tab
   - Find "name" attribute
   - Set it as "Required" or "Optional" (required will show in form)
   - Ensure "Mutable" is checked if users should be able to change it later

#### Option 2: Via AWS Console - Sign-up Experience (✅ RECOMMENDED FOR EXISTING POOLS)

**Step-by-step guide to add "name" field to Hosted UI:**

1. **Open AWS Console**: https://console.aws.amazon.com/cognito/
2. **Select Region**: Make sure you're in `us-east-2` (or your User Pool's region)
3. **Select User Pool**: Click on `us-east-2_IhW7EGoIg` (or your User Pool name)
4. **Navigate to Sign-up experience**:
   - In the left sidebar, click **"App integration"**
   - Click on the **"Sign-up experience"** tab
5. **Configure Required Attributes**:
   - Scroll down to the **"Required attributes"** section
   - You'll see checkboxes for: email, phone_number, name, etc.
   - **Check the box next to "name"**
6. **Save Changes**:
   - Click the **"Save changes"** button at the bottom
   - Wait for the confirmation message

**Result**: The "name" field will now appear in the Cognito Hosted UI sign-up form.

**Note**: This is the ONLY way to add standard attributes to existing User Pools. AWS CLI does not support this operation.

#### Option 3: Via Terraform/CloudFormation (Infrastructure as Code)

**Using Terraform:**

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
  name         = "balansi-client"
  user_pool_id = aws_cognito_user_pool.main.id

  # ... other client settings
}
```

**Note**: Standard attributes like "name" are already available in Cognito. You just need to:
1. Mark it as required in the User Pool schema (via Terraform/CloudFormation)
2. OR configure it in the Sign-up experience via Console (Option 2)

#### For cognito-local (Development)

The script `setup-cognito.sh` already includes "name" in the schema:

```bash
--schema \
  Name=email,AttributeDataType=String,Required=true \
  Name=name,AttributeDataType=String,Required=false \
  Name=nickname,AttributeDataType=String,Required=false
```

To make "name" **required** in the sign-up form, change `Required=false` to `Required=true`:

```bash
--schema \
  Name=email,AttributeDataType=String,Required=true \
  Name=name,AttributeDataType=String,Required=true \
  Name=nickname,AttributeDataType=String,Required=false
```

**Important Notes:**
- Standard attributes (`name`, `email`, `phone_number`, etc.) are built-in to Cognito
- Custom attributes require the `custom:` prefix (e.g., `custom:professional_id`)
- **⚠️ CRITICAL**: You **CANNOT** modify standard attributes in existing User Pools via AWS CLI
- The `update-user-pool` command does NOT support `--schema` parameter for standard attributes
- **For existing User Pools**: You MUST use the AWS Console (see Option 2 above)
- Required attributes will appear in the Hosted UI sign-up form
- Optional attributes can be collected but won't appear by default (can be added via API)

**✅ Solution for Existing User Pool (us-east-2_IhW7EGoIg):**

Since you cannot use AWS CLI, follow these steps in the Console:

1. **Go to AWS Console**: https://console.aws.amazon.com/cognito/
2. **Select your User Pool**: `us-east-2_IhW7EGoIg`
3. **Navigate to Sign-up experience**:
   - Click on **"App integration"** in the left menu
   - Click on **"Sign-up experience"** tab
4. **Configure Required Attributes**:
   - Scroll to **"Required attributes"** section
   - Check the box next to **"name"**
5. **Save Changes**: Click **"Save changes"** button

That's it! The "name" field will now appear in the Cognito Hosted UI sign-up form.

**Alternative**: If you need to automate this, you would need to:
- Use Terraform/CloudFormation to recreate the User Pool with the correct schema
- Or use AWS SDK/API to update the Sign-up experience configuration (more complex)

---

## 10. Environment Variables

### 10.1 Backend (Elixir)

```bash
# Cognito Configuration
COGNITO_USER_POOL_ID=us-east-2_XXXXXXXXX
COGNITO_CLIENT_ID=xxxxxxxxxxxxxxxxxxxxx
COGNITO_CLIENT_SECRET=xxxxxxxxxxxxxxxxxxxxx  # If client has secret
COGNITO_DOMAIN=auth.balansi.me  # Or default domain
COGNITO_REGION=us-east-2
COGNITO_REDIRECT_URI=https://app.balansi.me/auth/callback

# Database
DATABASE_URL=postgresql://user:pass@localhost/balansi

# Frontend
FRONTEND_URL=https://app.balansi.me
```

### 10.2 Frontend (Svelte)

```bash
# Cognito Configuration
VITE_COGNITO_CLIENT_ID=xxxxxxxxxxxxxxxxxxxxx
VITE_COGNITO_DOMAIN=auth.balansi.me
VITE_COGNITO_REGION=us-east-2
VITE_COGNITO_REDIRECT_URI=https://app.balansi.me/auth/callback

# API
VITE_API_URL=https://api.balansi.me
VITE_JOURNAL_API_URL=https://journal-api.balansi.me
```

---

## 11. Security Considerations

### 11.1 Token Security

- **Access Tokens**: Stored in memory only (not localStorage)
- **Refresh Tokens**: Stored in httpOnly cookies (prevents XSS)
- **Token Expiration**: Access tokens expire in 1 hour (Cognito default)
- **Automatic Refresh**: Tokens refreshed 5 minutes before expiration

### 11.2 State Parameter

- **Encoding**: URL-encode state parameter before sending to Cognito
- **Validation**: Validate state parameter in callback (prevent CSRF)
- **Size Limit**: Cognito supports state up to 2048 characters

### 11.3 HTTPS

- **Production**: All endpoints must use HTTPS
- **Development**: Can use HTTP for localhost only

### 11.4 CORS

- Configure CORS to allow only frontend domain
- Include credentials (cookies) in CORS configuration

---

## 12. Error Handling

### 12.1 Callback Errors

If callback fails:
- Log error details
- Redirect to login with error message
- Show user-friendly error page

### 12.2 Token Refresh Errors

If token refresh fails:
- Clear stored tokens
- Redirect to Cognito login
- Show "Session expired" message

### 12.3 API Errors

If API returns 401:
- Attempt token refresh
- If refresh fails, redirect to login
- Show "Authentication required" message

---

## 13. Testing

### 13.1 Unit Tests

- Token validation logic
- State parameter parsing
- User/patient creation logic

### 13.2 Integration Tests

- Callback endpoint flow
- Token refresh flow
- Protected route access

### 13.3 E2E Tests

- Complete signup flow (Cognito → Callback → Onboarding)
- Complete login flow (Cognito → Callback → Home)
- Token refresh on API call
- Protected route redirect

---

## 14. Migration Notes

### 14.1 From Custom Forms to Hosted UI

**Steps:**
1. Remove custom auth pages from frontend
2. Implement Cognito redirect logic
3. Implement callback endpoint in backend
4. Update token refresh logic
5. Add JWT validation plug to Journal API
6. Test complete flow

### 14.2 Database Migration

**New Tables:**
- `patients` table (see section 3.2)

**Users Table Changes:**
- Remove `temporary_password` field
- Remove `status` field
- Make `cognito_id` NOT NULL
- Add unique index on `cognito_id`

---

## 15. Summary

**Key Simplifications:**
- ✅ No custom auth forms (uses Cognito Hosted UI)
- ✅ Single callback endpoint handles all post-authentication logic
- ✅ Automatic token refresh in frontend
- ✅ JWT validation in Journal API using Cognito JWKS
- ✅ Simplified user model (no status field)
- ✅ Patient records created during authentication

**Benefits:**
- Less code to maintain
- Secure, compliant authentication forms
- Password policy handled by Cognito
- Reduced attack surface (no custom auth forms)

---

## 16. Implementation Plan

For a detailed, phase-by-phase implementation plan with specific PRs, see:
- **[Implementation Plan](./implementation-plan.md)** - 15 phases, each with max 5 files and 500 lines

**Quick Summary:**
- **Phase 1-2**: Database migrations and schemas
- **Phase 3-4**: Cognito client and auth context
- **Phase 5-6**: Callback and refresh endpoints
- **Phase 7-8**: JWT validation plug and router integration
- **Phase 9-14**: Frontend changes (remove pages, add redirects, token management)
- **Phase 15**: Environment variables and configuration

Each phase is designed to be:
- Small (max 5 files, 500 lines)
- Independent (can merge directly to main)
- Testable (includes tests)

---

**Document Version**: 2.0
**Last Updated**: 2025
**Status**: Draft - Pending Review
