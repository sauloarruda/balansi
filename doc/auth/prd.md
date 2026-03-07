# Product Requirements Document — Authentication (Balansi)

## Summary

Balansi uses local authentication with `rodauth-rails`. The application owns the auth UI, account creation, session lifecycle and user provisioning.

The current spike supports:
- email/password sign up
- email/password sign in
- sign out
- remember-me style persistent sessions via Rodauth's `remember` feature
- automatic `Patient` provisioning after sign up
- browser-language handling for unauthenticated auth pages

## Goals

- Provide a simple first-party auth flow inside the Rails app
- Keep authentication pages localized for unauthenticated users based on browser language
- Reuse Rails sessions and `session[:user_id]` as the application auth primitive
- Create the domain records required by Balansi immediately after sign up
- Keep the implementation compatible with the existing patient/professional onboarding model

## Non-Goals 

- External OAuth providers
- Social login
- MFA / WebAuthn
- Email verification
- Password reset / forgot password
- Account lockout / unlock flow
- Active session management UI
- Turning Balansi into an OAuth/OIDC provider

## Current User Flows

### Sign up

A new user can create an account at `/auth/sign_up` with:
- name
- email
- email confirmation
- password
- password confirmation

During sign up the app:
- validates locale/timezone defaults from the browser
- stores `name`, `email`, `timezone`, and `language` on `User`
- hashes the password using Rodauth
- creates a `Patient` record for the user
- links the patient to the selected `professional_id` when present, otherwise to the first available professional

### Sign in

An existing user signs in at `/auth/sign_in` with email and password.

On success the app:
- establishes a Rails session
- stores the authenticated user id in `session[:user_id]`
- optionally extends the session through Rodauth's `remember` feature

### Sign out

A signed-in user signs out via `POST /auth/sign_out`.

On success the app:
- clears the authenticated session
- redirects back to `/auth/sign_in`

## Security Requirements

- Password hashing must be handled by Rodauth/bcrypt
- Session cookies remain the application auth boundary
- Unauthenticated auth pages must respect browser locale (`pt` and `en`)
- Signup must reject invalid professional context instead of silently creating broken domain state
- Rate limiting must exist at the edge for signup abuse and generic request abuse

## Product Constraints

- The app must keep using the existing `User`, `Patient`, and `Professional` models
- The authenticated application continues to depend on `current_user` via `session[:user_id]`
- Auth pages must use the same view stack conventions as the rest of the app: `slim`, `tailwind`, `i18n`

## Open Follow-Ups

- Decide whether v1 needs `verify_account`
- Decide whether v1 needs `reset_password`
- Decide whether account lockout should be implemented via Rodauth `lockout`

**Document Version**: 2.0  
**Last Updated**: 2026-03-07  
**Status**: Rodauth spike
