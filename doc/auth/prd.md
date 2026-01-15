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
- Implement all authentication endpoints in Ruby on Rails

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

- **Sign Up**: User registration with name, email, and password (handled by Cognito Hosted UI)
- **Email Confirmation**: Code verification after sign-up (handled by Cognito)
- **Sign In**: Login with email and password, creating Rails session (handled by Cognito Hosted UI)
- **Session Management**: Rails native session with httpOnly cookies
- **Authentication Check**: Rails before_action to verify session on protected routes
- **Forgot Password**: Initiate password recovery via email code (handled by Cognito Hosted UI)
- **Reset Password**: Complete password reset with code and new password (handled by Cognito Hosted UI)
- **Auto-Create Records**: User and Patient records created automatically during callback (onboarding to be implemented later)
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
- Languages other than pt-BR and en (supported languages in v1: pt-BR, en)

## 8. Non-Functional Requirements

### 8.1 Security

- **Password Policy**: Enforce Cognito password requirements (8+ chars, uppercase, lowercase, number, special char)
- **User Enumeration Protection**: Forgot password always returns success, even if user doesn't exist
- **Session Security**: Rails session cookies are httpOnly, Secure (in production), and SameSite=Lax by default
- **Session Storage**: Rails native session stored in encrypted httpOnly cookies (no tokens in frontend)
- **HTTPS**: All authentication endpoints must use HTTPS in production
- **Rate Limiting**: Cognito handles rate limiting; frontend should handle 429 responses gracefully

### 8.2 Performance

- **Fast Initial Load**: Authentication pages should load quickly (< 1s)
- **Session Persistence**: Rails session persists across requests until expiration
- **Minimal Implementation**: Leverages 100% of Cognito features, minimal code in Rails
- **Low Latency**: Services must be hosted in Brazil (South America region) to minimize network latency for Brazilian users

### 8.3 Usability

- **Clear Error Messages**: All errors must be user-friendly and actionable
- **Validation Feedback**: Real-time validation on form fields
- **Loading States**: Show loading indicators during API calls
- **Accessibility**: Forms must be accessible (keyboard navigation, screen readers)
- **Localization**: System detects browser language (Accept-Language header) and uses pt-BR or en for Cognito Hosted UI. If browser language cannot be detected or is not pt-BR or en, defaults to pt-BR. Application supports translations for pt-BR and en in v1

### 8.4 Reliability

- **Error Handling**: Graceful handling of network errors, API failures
- **Retry Logic**: Automatic retry for transient failures (with exponential backoff)
- **Session Recovery**: If session expires, redirect to sign-in (don't show cryptic errors)

### 8.5 Compatibility

- **Browser Support**: Modern browsers (Chrome, Firefox, Safari, Edge - last 2 versions)
- **Mobile Responsive**: All auth pages must work on mobile devices
- **Cookie Support**: Requires cookies to be enabled

### 8.6 Infrastructure Requirements

- **Hosting Location**: All services (Rails application, Cognito User Pool, database) must be hosted in Brazil (AWS South America - São Paulo region: sa-east-1) to minimize network latency for Brazilian users
- **Cognito Region**: AWS Cognito User Pool must be created in the sa-east-1 region
- **Language Detection**: Browser language (Accept-Language header) is detected when redirecting to Cognito. Supported languages: pt-BR, en. Default: pt-BR if not detected or not supported
- **Infrastructure as Code (IaC)**: All infrastructure must be defined using Terraform with separate configurations for development, staging, and production environments

### 8.7 Internationalization (i18n)

- **Supported Languages (v1)**: Portuguese (Brazil) - pt-BR, English - en
- **Language Detection**: Browser language is detected from Accept-Language header when redirecting to Cognito Hosted UI
- **Fallback Strategy**: If browser language cannot be detected or is not pt-BR or en, defaults to pt-BR
- **Application Translations**: Rails application must have translations for pt-BR and en using Rails i18n system
- **Cognito Language**: Cognito Hosted UI pages use detected language (pt-BR or en) or default to pt-BR

---

---

## 9. Open Questions / Decisions Needed

1. **Sign-in Endpoint**: Authentication handled by Cognito Hosted UI, callback implemented in Rails (Decision: Use Rails for callback processing)

2. **Session Cookie Domain**: Should session cookies be scoped to specific domain or allow cross-subdomain? (Decision: Based on deployment architecture)

3. **Password Requirements Display**: Should password requirements be shown inline or in a tooltip? (Decision: Inline for better UX)

4. **Session Management**: Use Rails native session management with httpOnly cookies (Decision: Rails session, no JWT tokens in frontend)

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
- Account management (profile updates, email change)
- Active sessions management
- Security audit log

---

**Document Version**: 1.0
**Last Updated**: 2026 Jan
**Status**: Draft - Pending Review
