# Engineering Requirements Document — Authentication (Balansi)

## Architecture Overview

Balansi authentication is implemented inside the Rails monolith with `rodauth-rails`.

### Main components

- `Rodauth::Rails::Middleware`: intercepts `/auth/*` before the Rails router
- `RodauthMain`: auth configuration, messages and signup provisioning rules
- `RodauthController`: Rails wrapper for layout, CSRF, locale and controller callbacks
- `User`: account record with password hash and locale/timezone defaults
- `Patient`: domain record created automatically after successful account creation
- `user_remember_keys`: persistence table for Rodauth's `remember` feature

### Enabled Rodauth features

- `create_account`
- `login`
- `logout`
- `remember`

### Not enabled in this spike

- `verify_account`
- `reset_password`
- `lockout`
- MFA-related features

## Data Model

### users

| Field | Type | Notes |
| --- | --- | --- |
| `id` | integer | primary key |
| `name` | string | required |
| `email` | string | required, unique |
| `password_hash` | string | managed by Rodauth |
| `timezone` | string | required, default `America/Sao_Paulo` |
| `language` | string | required, default `pt` |
| `created_at` | datetime | required |
| `updated_at` | datetime | required |

### user_remember_keys

| Field | Type | Notes |
| --- | --- | --- |
| `id` | integer | foreign key to `users.id`, primary key |
| `key` | string | remember token digest data |
| `deadline` | datetime | remember session expiry |

### patients

`Patient` is not an auth table, but it is part of the signup side effect. A user created through `/auth/sign_up` is immediately provisioned as a patient and linked to a professional.

## Relationships

```text
users (1) ---- (0..1) professionals
users (1) ---- (0..1) patients
users (1) ---- (0..1) user_remember_keys
patients (*) -- (1) professionals
```

## Request Flow

### Sign up

1. Browser requests `GET /auth/sign_up`
2. Rodauth renders the local signup form through `RodauthController`
3. Browser submits `POST /auth/sign_up`
4. `RodauthMain` validates:
   - email/password requirements
   - name presence
   - timezone validity
   - language validity
   - professional context
5. Rodauth creates the `users` row
6. `after_create_account` creates the `patients` row
7. User session is established and the app redirects to `/`

### Sign in

1. Browser requests `GET /auth/sign_in`
2. Rodauth renders the local login form
3. Browser submits `POST /auth/sign_in`
4. Rodauth validates email/password against `users.password_hash`
5. The app stores the authenticated account id in `session[:user_id]`
6. The app redirects to `/`

### Sign out

1. Browser submits `POST /auth/sign_out`
2. Rodauth clears the authenticated session
3. The app redirects to `/auth/sign_in`

## Locale And Timezone Rules

- Unauthenticated auth pages use browser language detection from `BrowserLanguage`
- Supported locales are `pt` and `en`
- New accounts default timezone from the `timezone` cookie, falling back to `America/Sao_Paulo`
- New accounts default language from browser detection, falling back to `pt`

## Key Files

- `app/misc/rodauth_main.rb`
- `app/misc/rodauth_app.rb`
- `app/controllers/rodauth_controller.rb`
- `app/models/user.rb`
- `app/views/rodauth/login.html.slim`
- `app/views/rodauth/create_account.html.slim`
- `db/migrate/20260306213448_create_rodauth.rb`

## Operational Notes

- Auth route helpers are defined as direct routes in `config/routes.rb` because the middleware owns `/auth/*`
- Rack::Attack protects signup flooding and generic request abuse
- Application auth still relies on `current_user` via `session[:user_id]`
- Development-only `?test_user_id=` bypass remains available for local exploration

**Document Version**: 2.0  
**Last Updated**: 2026-03-07  
**Status**: Rodauth spike
