# Product Requirements Document — Authentication (Balansi)

## 1. Summary

The **Authentication** module provides secure user registration, login, and password management for the Balansi platform. It integrates with AWS Cognito for identity management and implements a cookie-based session system for secure token storage.

The authentication system must be:
- secure and compliant with best practices,
- user-friendly with clear error messages,
- resilient to common attacks (user enumeration, brute force, etc.),
- and provide a seamless experience across sign-up, confirmation, login, and password recovery flows.

---

## 2. Goals & Non-Goals

### 2.1 Goals

- Allow new users to register with name, email, and password
- Require email confirmation before allowing login
- Provide secure login with email and password
- Implement password recovery flow (forgot password + reset password)
- Maintain secure session management using httpOnly cookies
- Protect against user enumeration attacks
- Validate passwords according to Cognito policy requirements
- Implement all authentication endpoints in Elixir API

### 2.2 Non-Goals (for v1)

- Social login (Google, Facebook, etc.)
- Multi-factor authentication (MFA)
- Password strength meter UI (validation happens server-side)
- Remember me / persistent sessions beyond cookie expiration
- Account deletion / deactivation flows
- Email change flows
- Username-based login (email only)

---

## 3. Users & Personas

### 3.1 New User (Signing Up)

- Wants: quick registration, clear confirmation process
- Needs:
  - simple sign-up form
  - clear instructions for email confirmation
  - immediate feedback on validation errors

### 3.2 Returning User (Signing In)

- Wants: fast login, password recovery if forgotten
- Needs:
  - simple login form
  - easy access to password recovery
  - clear error messages for invalid credentials

### 3.3 User Recovering Password

- Wants: straightforward password reset process
- Needs:
  - clear instructions for code entry
  - password requirements clearly displayed
  - confirmation that reset was successful

---

## 4. Scope

### 4.1 In Scope

- **Sign Up**: User registration with name, email, and password
- **Email Confirmation**: Code verification after sign-up
- **Sign In**: Login with email and password, creating session cookies
- **Session Management**: Cookie-based authentication with refresh token flow
- **Authentication Check**: Middleware to verify session on protected routes
- **Forgot Password**: Initiate password recovery via email code
- **Reset Password**: Complete password reset with code and new password
- **Password Validation**: Enforce Cognito password policy (8+ chars, uppercase, lowercase, number, special char)
- **Error Handling**: User-friendly error messages with proper HTTP status codes
- **User Enumeration Protection**: Generic responses for forgot password to prevent user enumeration

### 4.2 Out of Scope (v1)

- Social authentication providers
- Multi-factor authentication
- Account management (profile updates, email change)
- Session management UI (active sessions list)
- Password history / reuse prevention
- Account lockout after failed attempts (handled by Cognito)

---

## 5. Functional Requirements

### 5.1 Sign Up

**FR-SU-01**: The user can access the sign-up page at `/auth/sign-up`.

**FR-SU-02**: The sign-up form must collect:
- **Name**: User's preferred name (minimum 2 characters, required)
- **Email**: Valid email address (required, validated format)
- **Password**: Must meet Cognito password policy requirements:
  - At least 8 characters
  - At least one uppercase letter
  - At least one lowercase letter
  - At least one number
  - At least one special character (!@#$%^&*)
- **Password Confirmation**: Must match the password field

**FR-SU-03**: The form must validate inputs client-side before submission:
- Name: minimum 2 characters
- Email: valid email format
- Password: meets policy requirements (client-side validation as user types)
- Password confirmation: matches password

**FR-SU-03a**: The password field must include a password strength meter component that:
- Shows real-time feedback as the user types
- Indicates which requirements are met (uppercase, lowercase, number, special char, length)
- Provides visual feedback (e.g., color-coded strength indicator)
- Helps users understand password requirements before submission

**FR-SU-04**: On successful sign-up:
- User receives a confirmation email with a 6-digit code
- User is redirected to `/auth/confirmation` page
- User's email, name, and userId are stored temporarily (localStorage) for confirmation flow

**FR-SU-05**: On sign-up failure:
- If email already exists (409), show error and suggest redirecting to login
- If validation fails (400), show specific field errors
- If server error (500), show generic error message

**FR-SU-06**: The sign-up endpoint (`POST /auth/sign-up`) creates a user in:
- AWS Cognito (identity provider)
- Local database (user record with status: pending_confirmation)

**FR-SU-07**: The sign-up endpoint does NOT require authentication.

---

### 5.2 Email Confirmation

**FR-EC-01**: After sign-up, the user is redirected to `/auth/confirmation`.

**FR-EC-02**: The confirmation page displays:
- User's name and email (from temporary storage)
- Instructions to check email for 6-digit code
- PIN input field (6 digits)

**FR-EC-03**: The user enters the 6-digit confirmation code received via email.

**FR-EC-04**: On successful confirmation:
- User's Cognito account is confirmed
- Session cookie (`session_id`) is created with encrypted refresh token
- User is redirected to home page (`/`)
- Temporary auth data is cleared from localStorage

**FR-EC-05**: On confirmation failure:
- Invalid code (422): Show error message
- Expired code (422): Show error message with option to resend
- User already confirmed (409): Redirect to login page
- User not found (404): Redirect to sign-up page

**FR-EC-06**: The confirmation endpoint (`POST /auth/confirm`) requires:
- `userId`: The user ID returned during sign-up
- `code`: The 6-digit confirmation code

**FR-EC-07**: After confirmation, the session cookie is set with:
- Name: `session_id`
- Value: Encrypted session data (refresh token, user ID, username)
- HttpOnly: true
- SameSite: Lax (or None for cross-domain if needed)
- Secure: true (in production)
- Max-Age: 30 days (2592000 seconds)

**FR-EC-08**: After setting the session cookie, the frontend must call `/auth/refresh` to obtain an access token for API calls.

---

### 5.3 Sign In

**FR-SI-01**: The user can access the sign-in page at `/auth/sign-in`.

**FR-SI-02**: The sign-in form must collect:
- **Email**: Valid email address (required)
- **Password**: User's password (required)

**FR-SI-03**: On successful sign-in:
- User's credentials are validated against Cognito
- Session cookie (`session_id`) is created with encrypted refresh token
- User is redirected to home page (`/`)
- Access token is obtained via `/auth/refresh` call

**FR-SI-04**: On sign-in failure:
- Invalid credentials (401): Show generic error (do not reveal if email exists)
- User not confirmed (403): Show error with link to resend confirmation
- User not found (404): Show generic error (same as invalid credentials for security)
- Server error (500): Show generic error message

**FR-SI-05**: The sign-in endpoint must:
- Authenticate user with Cognito using email and password
- Create session cookie similar to confirmation flow
- Return success response

**FR-SI-06**: The sign-in page must include a link to `/auth/forgot-password` for password recovery.

**FR-SI-07**: If user is already authenticated (has valid session), redirect to home page.

---

### 5.4 Check Authentication (Session Validation)

**FR-CA-01**: All frontend routes except `/auth/*` must verify authentication before allowing access.

**FR-CA-02**: Authentication check must:
- Read `session_id` cookie from request
- Call `/auth/refresh` endpoint to validate session and obtain access token
- If sessiokn is valid, store access toen for subsequent API calls
- If session is invalid/expired, redirect to `/auth/sign-in`

**FR-CA-03**: The `/auth/refresh` endpoint:
- Extracts `session_id` cookie
- Decrypts session data to get refresh token
- Calls Cognito to refresh access token
- Returns new access token and expiration time

**FR-CA-04**: On authentication failure:
- Missing cookie (401): Redirect to `/auth/sign-in`
- Invalid session (401): Redirect to `/auth/sign-in`
- User not confirmed (403): Redirect to `/auth/confirmation` or show error
- Token refresh failed (401): Redirect to `/auth/sign-in`

**FR-CA-05**: All API calls to protected endpoints (e.g., `/journal/*`) must include:
- `Authorization: Bearer <access_token>` header
- Access token obtained from `/auth/refresh` call

**FR-CA-06**: If API returns 401 (Unauthorized):
- Clear session cookie
- Clear stored access token
- Redirect to `/auth/sign-in`

**FR-CA-07**: The access token must be refreshed automatically before expiration (or on 401 response).

---

### 5.5 Forgot Password

**FR-FP-01**: The user can access the forgot password page at `/auth/forgot-password`.

**FR-FP-02**: The forgot password form must collect:
- **Email**: Valid email address (required)

**FR-FP-03**: On submission:
- System checks if user exists in database
- If user exists, sends password recovery code via email via Cognito
- Always returns success response (200) to prevent user enumeration

**FR-FP-04**: Response always includes:
- `success: true`
- `destination: <email>` (echoed from request)
- `deliveryMedium: "EMAIL"`

**FR-FP-05**: On successful request:
- User receives email with 6-digit recovery code
- User is redirected to `/auth/reset-password` page
- Email is stored temporarily for reset password flow

**FR-FP-06**: Error handling (for logging only, client always sees success):
- User not found: Log warning, return success to client
- Too many attempts (429): Return error to client
- Rate limit exceeded (429): Return error to client
- Server error (500): Return generic error

**FR-FP-07**: The forgot password endpoint (`POST /auth/forgot-password`) follows the same security rules as the Go implementation:
- Checks user existence in database first
- Calls Cognito `ForgotPassword` API
- Maps Cognito errors to application errors
- Returns generic success even if user doesn't exist (user enumeration protection)

---

### 5.6 Reset Password

**FR-RP-01**: The user can access the reset password page at `/auth/reset-password`.

**FR-RP-02**: The reset password form must collect:
- **Code**: 6-digit recovery code from email (required)
- **New Password**: Must meet Cognito password policy (same as sign-up)
- **Password Confirmation**: Must match new password

**FR-RP-03**: The form must display password requirements clearly:
- At least 8 characters
- At least one uppercase letter
- At least one lowercase letter
- At least one number
- At least one special character (!@#$%^&*)

**FR-RP-04**: On successful reset:
- Password is updated in Cognito
- User is redirected to `/auth/sign-in` page
- Success message is displayed

**FR-RP-05**: On reset failure:
- Invalid code (422): Show error message
- Expired code (422): Show error message with option to request new code
- Password policy violation (400): Show specific password requirements
- Too many attempts (429): Show error with retry instructions
- User not found (404): Redirect to sign-up page

**FR-RP-06**: The reset password endpoint (`POST /auth/reset-password`) requires:
- `email`: User's email address
- `code`: 6-digit recovery code
- `newPassword`: New password meeting policy requirements

**FR-RP-07**: The reset password endpoint follows the same error mapping as the Go implementation:
- `CodeMismatchException` → `recovery_code_invalid` (422)
- `ExpiredCodeException` → `recovery_code_expired` (422)
- `InvalidPasswordException` → `password_policy_violation` (400)
- `UserNotFoundException` → `user_not_found` (404)
- `LimitExceededException` → `limit_exceeded` (429)
- `TooManyFailedAttemptsException` → `too_many_attempts` (429)

### 5.7 Logout

**FR-LO-01**: The user can logout from any authenticated page by clicking a logout button or action.

**FR-LO-02**: On logout:
- Frontend clears the access token from memory
- Frontend calls `POST /auth/logout` endpoint
- Backend invalidates the `session_id` cookie by setting `Max-Age=-1`
- User is redirected to `/auth/sign-in` page

**FR-LO-03**: The logout endpoint (`POST /auth/logout`):
- Does NOT require authentication (can be called even if session is invalid)
- Sets `session_id` cookie with `Max-Age=-1` to expire it immediately
- Cookie attributes:
  - `Path=/`
  - `HttpOnly=true`
  - `SameSite=None; Secure` (in production/HTTPS)
  - `SameSite=Lax` (in local development/HTTP)
- Returns success response: `{"success": true}`

**FR-LO-04**: The logout action must:
- Clear access token from memory (prevent automatic refresh)
- Clear any stored authentication data
- Redirect user to sign-in page
- Handle errors gracefully (even if backend call fails, clear local state)

**FR-LO-05**: After logout:
- User cannot access protected routes
- Any attempt to access protected routes redirects to `/auth/sign-in`
- Session cookie is invalidated (cannot be used for refresh)

**FR-LO-06**: The logout button should be:
- Visible on authenticated pages (e.g., home page, user menu)
- Clearly labeled (e.g., "Logout", "Sign Out")
- Provide visual feedback during logout process (loading state)

---

## 6. User Flows

### 6.1 Flow: New User Registration and Confirmation

1. User navigates to `/auth/sign-up`
2. User fills in:
   - Name
   - Email
   - Password
   - Password Confirmation
3. Form validates inputs client-side
4. User submits form
5. System creates user in Cognito and database
6. User receives confirmation email with 6-digit code
7. User is redirected to `/auth/confirmation`
8. Confirmation page displays user's name and email
9. User checks email for 6-digit code
10. User enters code in PIN input
11. System validates code with Cognito
12. On success:
    - User's Cognito account is confirmed
    - Session cookie (`session_id`) is created with encrypted refresh token
    - Frontend calls `/auth/refresh` to get access token
    - Temporary auth data is cleared from localStorage
    - User is redirected to home page (`/`)
13. On failure:
    - Invalid code (422): Error message is displayed, user can retry
    - Expired code (422): Error message is displayed with option to request new code
    - User already confirmed (409): User is redirected to login page
    - User not found (404): User is redirected to sign-up page

### 6.2 Flow: User Login

1. User navigates to `/auth/sign-in`
2. User enters email and password
3. System authenticates with Cognito
4. On success:
   - Session cookie is created
   - Access token is obtained via `/auth/refresh`
   - User is redirected to home page
5. On failure:
   - Generic error message is shown
   - User can retry or use "Forgot Password" link

### 6.3 Flow: Password Recovery

1. User clicks "Forgot Password" link on sign-in page
2. User navigates to `/auth/forgot-password`
3. User enters email address
4. System sends recovery code via email (if user exists)
5. Always shows success message (user enumeration protection)
6. User is redirected to `/auth/reset-password`
7. User enters:
   - 6-digit recovery code
   - New password
   - Password confirmation
8. System validates and resets password
9. On success:
   - User is redirected to `/auth/sign-in`
   - Success message is displayed
10. On failure:
    - Error message is shown
    - User can retry or request new code

### 6.4 Flow: Protected Route Access

1. User navigates to any route except `/auth/*`
2. System checks for `session_id` cookie
3. If cookie exists:
   - System calls `/auth/refresh` to validate session
   - If valid, access token is stored
   - User can access the route
4. If cookie missing or invalid:
   - User is redirected to `/auth/sign-in`
5. On API calls to protected endpoints:
   - Access token is included in `Authorization` header
   - If token expires (401), refresh is attempted
   - If refresh fails, user is redirected to sign-in

---

## 7. Screens (High-Level)

### 7.1 Sign Up Screen (`/auth/sign-up`)

- **Header**: "Create Account" or similar
- **Form Fields**:
  - Name input (text, required, min 2 chars)
  - Email input (email, required)
  - Password input (password, required, with requirements shown)
  - Password Confirmation input (password, required)
- **Actions**:
  - Submit button (disabled until form valid)
  - Link to sign-in page ("Already have an account? Sign in")
- **Validation**:
  - Real-time validation feedback
  - Password strength indicator (optional, but requirements must be visible)
- **Error Display**: Error message area for API errors

### 7.2 Confirmation Screen (`/auth/confirmation`)

- **Header**: "Confirm Your Email" or similar
- **Content**:
  - Personalized message: "Hi {name}, we sent a code to {email}"
  - Instructions: "Enter the 6-digit code from your email"
- **Form**:
  - PIN input component (6 digits)
  - Submit button
- **Actions**:
  - Resend code link (if needed)
- **Error Display**: Error message area

### 7.3 Sign In Screen (`/auth/sign-in`)

- **Header**: "Sign In" or similar
- **Form Fields**:
  - Email input (email, required)
  - Password input (password, required)
- **Actions**:
  - Submit button
  - "Forgot Password?" link
  - Link to sign-up page ("Don't have an account? Sign up")
- **Error Display**: Error message area

### 7.4 Forgot Password Screen (`/auth/forgot-password`)

- **Header**: "Reset Your Password" or similar
- **Content**: Instructions about receiving recovery code
- **Form Fields**:
  - Email input (email, required)
- **Actions**:
  - Submit button
  - Link back to sign-in page
- **Success Message**: "If an account exists, a recovery code has been sent to your email"

### 7.5 Reset Password Screen (`/auth/reset-password`)

- **Header**: "Set New Password" or similar
- **Form Fields**:
  - Code input (6-digit PIN)
  - New Password input (password, required)
  - Password Confirmation input (password, required)
- **Password Requirements**: Visible list of requirements
- **Actions**:
  - Submit button
  - Link to request new code (if code expired)
- **Error Display**: Error message area

---

## 8. Non-Functional Requirements

### 8.1 Security

- **Password Policy**: Enforce Cognito password requirements (8+ chars, uppercase, lowercase, number, special char)
- **User Enumeration Protection**: Forgot password always returns success, even if user doesn't exist
- **Session Security**: Session cookies must be httpOnly, Secure (in production), and SameSite=Lax
- **Token Storage**: Access tokens stored in memory (not localStorage) to prevent XSS attacks
- **HTTPS**: All authentication endpoints must use HTTPS in production
- **Rate Limiting**: Cognito handles rate limiting; frontend should handle 429 responses gracefully

### 8.2 Performance

- **Fast Initial Load**: Authentication pages should load quickly (< 1s)
- **Token Refresh**: Automatic token refresh before expiration (with 5-minute buffer)
- **Minimal API Calls**: Cache access token until near expiration

### 8.3 Usability

- **Clear Error Messages**: All errors must be user-friendly and actionable
- **Validation Feedback**: Real-time validation on form fields
- **Loading States**: Show loading indicators during API calls
- **Accessibility**: Forms must be accessible (keyboard navigation, screen readers)

### 8.4 Reliability

- **Error Handling**: Graceful handling of network errors, API failures
- **Retry Logic**: Automatic retry for transient failures (with exponential backoff)
- **Session Recovery**: If session expires, redirect to sign-in (don't show cryptic errors)

### 8.5 Compatibility

- **Browser Support**: Modern browsers (Chrome, Firefox, Safari, Edge - last 2 versions)
- **Mobile Responsive**: All auth pages must work on mobile devices
- **Cookie Support**: Requires cookies to be enabled

---

---

## 9. Open Questions / Decisions Needed

1. **Sign-in Endpoint**: Should sign-in be implemented in Elixir API or continue using Go API? (Decision: Implement in Elixir to consolidate auth logic)

2. **Session Cookie Domain**: Should session cookies be scoped to specific domain or allow cross-subdomain? (Decision: Based on deployment architecture)

3. **Password Requirements Display**: Should password requirements be shown inline or in a tooltip? (Decision: Inline for better UX)

4. **Token Refresh Strategy**: Should tokens be refreshed proactively or reactively? (Decision: Proactive with 5-minute buffer)

5. **Error Message Localization**: Should error messages be translated client-side or server-side? (Decision: Client-side using i18n system)

---

## 10. Success Metrics

- **Registration Completion Rate**: % of users who complete sign-up and confirmation
- **Login Success Rate**: % of successful login attempts
- **Password Recovery Success Rate**: % of users who successfully reset password
- **Session Reliability**: % of sessions that remain valid without unexpected logouts
- **Error Rate**: % of authentication requests that result in errors

---

## 11. Future Enhancements (Post-v1)

- Social login (Google, Facebook)
- Multi-factor authentication (MFA)
- Password strength meter with real-time feedback
- "Remember me" functionality with longer session duration
- Account management (profile updates, email change)
- Active sessions management
- Security audit log

---

**Document Version**: 1.0
**Last Updated**: 2025
**Status**: Draft - Pending Review
