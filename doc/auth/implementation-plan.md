# Implementation Plan — Cognito Hosted UI Authentication (BAL-11)

## Overview

This document outlines the implementation plan for migrating to Cognito Hosted UI authentication. Each phase is designed to be:
- **Small**: Maximum 5 files per PR
- **Focused**: Maximum 500 lines of changes per PR
- **Independent**: Can be merged directly to main
- **Testable**: Each phase includes tests

---

## Phase 1: Database Migrations (BAL-11.p1)

**Branch**: `BAL-11.p1`
**Target**: `main`
**Estimated Files**: 3 files
**Estimated Lines**: ~150 lines
**Status**: ✅ **Completed**

### Changes

1. **Create users table migration**
   - File: `services/journal/priv/repo/migrations/20251209114741_create_users_table.exs`
   - Creates `users` table with:
     - `id` (SERIAL, PRIMARY KEY)
     - `name` (VARCHAR(255), NOT NULL)
     - `email` (VARCHAR(255), NOT NULL, UNIQUE)
     - `cognito_id` (VARCHAR(255), NOT NULL, UNIQUE)
     - `inserted_at` and `updated_at` (timestamps)
   - Unique indexes: `users_email_key` and `users_cognito_id_key`
   - Comprehensive module documentation

2. **Create patients table migration**
   - File: `services/journal/priv/repo/migrations/20251209114742_create_patients_table.exs`
   - Creates `patients` table with:
     - `id` (SERIAL, PRIMARY KEY)
     - `user_id` (INTEGER, NOT NULL) - Foreign key to `users.id` with CASCADE delete (created inline)
     - `professional_id` (INTEGER, NOT NULL)
     - `inserted_at` and `updated_at` (timestamps)
   - Indexes: `patients_user_id_idx` and `patients_professional_id_idx`
   - Composite unique index: `patients_user_professional_unique_idx` on `(user_id, professional_id)`
   - Foreign key constraint: `patients.user_id` → `users.id` with `ON DELETE CASCADE` (created inline)
   - Comprehensive module documentation

3. **Add foreign key to meal_entries.patient_id**
   - File: `services/journal/priv/repo/migrations/20251209150327_add_foreign_key_to_meal_entries_patient_id.exs`
   - Adds FK constraint: `meal_entries.patient_id` → `patients.id` with `ON DELETE CASCADE`
   - Ensures referential integrity and automatic cleanup when patients are deleted

### Foreign Key Relationships

```
users (id)
  └─ patients.user_id → users.id [CASCADE DELETE]
      └─ meal_entries.patient_id → patients.id [CASCADE DELETE]
```

### Acceptance Criteria

- [x] Users table has correct schema (no temporary_password, no status)
- [x] Patients table created with correct schema
- [x] Foreign key constraints added with CASCADE delete
- [x] Composite unique index on patients(user_id, professional_id)
- [x] Migrations run successfully
- [x] Rollback migrations work
- [x] Documentation updated (ERD reflects FKs and timestamp precision)

---

## Phase 2: Elixir Schemas (BAL-11.p2)

**Branch**: `BAL-11.p2`
**Target**: `main`
**Estimated Files**: 3 files
**Estimated Lines**: ~200 lines

### Changes

1. **User schema**
   - File: `services/journal/lib/journal/auth/user.ex`
   - Schema with `name`, `email`, `cognito_id`
   - Changeset functions

2. **Patient schema**
   - File: `services/journal/lib/journal/auth/patient.ex`
   - Schema with `user_id`, `professional_id`
   - Changeset functions

3. **Test files**
   - File: `services/journal/test/journal/auth/user_test.exs`
   - File: `services/journal/test/journal/auth/patient_test.exs`

### Acceptance Criteria

- [ ] User schema validates correctly
- [ ] Patient schema validates correctly
- [ ] All tests pass
- [ ] Schemas can be inserted/updated via Repo

---

## Phase 3: Cognito Client Service (BAL-11.p3)

**Branch**: `BAL-11.p3`
**Target**: `main`
**Estimated Files**: 2 files
**Estimated Lines**: ~300 lines

### Changes

1. **Cognito client module**
   - File: `services/journal/lib/journal/auth/cognito_client.ex`
   - Functions:
     - `exchange_code_for_tokens/2` - Exchange authorization code for tokens
     - `get_user_info/1` - Get user info from Cognito
     - `refresh_access_token/1` - Refresh access token
   - Uses HTTP client (Finch/Req) to call Cognito endpoints

2. **Test file**
   - File: `services/journal/test/journal/auth/cognito_client_test.exs`
   - Mock Cognito responses

### Acceptance Criteria

- [ ] Can exchange code for tokens
- [ ] Can get user info from access token
- [ ] Can refresh access token
- [ ] All tests pass with mocks

---

## Phase 4: Auth Context Module (BAL-11.p4)

**Branch**: `BAL-11.p4`
**Target**: `main`
**Estimated Files**: 2 files
**Estimated Lines**: ~250 lines

### Changes

1. **Auth context**
   - File: `services/journal/lib/journal/auth.ex`
   - Functions:
     - `create_or_find_user/2` - Find or create user by cognito_id
     - `create_patient/2` - Create patient record
     - `get_first_professional_id/0` - Get first professional (temporary)
   - Uses Repo to interact with database

2. **Test file**
   - File: `services/journal/test/journal/auth_test.exs`

### Acceptance Criteria

- [ ] Can create or find user
- [ ] Can create patient record
- [ ] Handles duplicate user creation gracefully
- [ ] All tests pass

---

## Phase 5: Callback Controller (BAL-11.p5)

**Branch**: `BAL-11.p5`
**Target**: `main`
**Estimated Files**: 2 files
**Estimated Lines**: ~200 lines

### Changes

1. **Callback controller**
   - File: `services/journal/lib/journal_web/controllers/auth_controller.ex`
   - Action: `callback/2`
   - Handles Cognito redirect with code and state
   - Creates user and patient records
   - Sets refresh token cookie
   - Redirects to frontend

2. **Router update**
   - File: `services/journal/lib/journal_web/router.ex`
   - Add route: `get "/auth/callback", AuthController, :callback`

### Acceptance Criteria

- [ ] Callback endpoint handles code exchange
- [ ] Creates user and patient records
- [ ] Sets httpOnly cookie with refresh token
- [ ] Redirects to frontend URL
- [ ] Handles errors gracefully

---

## Phase 6: Token Refresh Endpoint (BAL-11.p6)

**Branch**: `BAL-11.p6`
**Target**: `main`
**Estimated Files**: 2 files
**Estimated Lines**: ~150 lines

### Changes

1. **Auth controller - refresh action**
   - File: `services/journal/lib/journal_web/controllers/auth_controller.ex`
   - Action: `refresh/2`
   - Reads refresh token from cookie
   - Calls Cognito to refresh access token
   - Returns new access token

2. **Router update**
   - File: `services/journal/lib/journal_web/router.ex`
   - Add route: `post "/auth/refresh", AuthController, :refresh`

### Acceptance Criteria

- [ ] Refresh endpoint reads cookie
- [ ] Returns new access token
- [ ] Handles invalid refresh token
- [ ] Returns correct expiration time

---

## Phase 7: JWT Validation Plug (BAL-11.p7)

**Branch**: `BAL-11.p7`
**Target**: `main`
**Estimated Files**: 2 files
**Estimated Lines**: ~400 lines

### Changes

1. **JWT validation plug**
   - File: `services/journal/lib/journal_web/plugs/verify_token.ex`
   - Validates JWT token signature using Cognito JWKS
   - Extracts cognito_id from token
   - Looks up user in database
   - Gets patient_id from user's patient record
   - Adds `current_user` and `current_patient_id` to conn.assigns

2. **JWKS fetcher module**
   - File: `services/journal/lib/journal/auth/jwks.ex`
   - Fetches and caches JWKS from Cognito
   - Validates token signature

### Acceptance Criteria

- [ ] Validates JWT token signature
- [ ] Extracts cognito_id correctly
- [ ] Looks up user in database
- [ ] Gets patient_id correctly
- [ ] Handles invalid/expired tokens
- [ ] Caches JWKS keys

---

## Phase 8: Integrate JWT Plug in Router (BAL-11.p8)

**Branch**: `BAL-11.p8`
**Target**: `main`
**Estimated Files**: 2 files
**Estimated Lines**: ~50 lines

### Changes

1. **Router - protected pipeline**
   - File: `services/journal/lib/journal_web/router.ex`
   - Create `:protected` pipeline with `VerifyToken` plug
   - Apply to meal routes

2. **Meal controller update**
   - File: `services/journal/lib/journal_web/controllers/meal_controller.ex`
   - Remove `@poc_patient_id` constant
   - Use `conn.assigns[:current_patient_id]` instead

### Acceptance Criteria

- [ ] Protected routes require valid JWT token
- [ ] Meal controller uses patient_id from token
- [ ] Returns 401 for invalid/missing tokens
- [ ] All existing tests updated and passing

---

## Phase 9: Remove Frontend Auth Pages (BAL-11.p9)

**Branch**: `BAL-11.p9`
**Target**: `main`
**Estimated Files**: 5 files
**Estimated Lines**: ~50 lines (deletions)

### Changes

1. **Delete auth pages**
   - File: `services/web/src/routes/auth/sign-up/+page.svelte` ❌
   - File: `services/web/src/routes/auth/sign-in/+page.svelte` ❌
   - File: `services/web/src/routes/auth/forgot-password/+page.svelte` ❌
   - File: `services/web/src/routes/auth/reset-password/+page.svelte` ❌
   - File: `services/web/src/routes/auth/confirmation/+page.svelte` ❌

### Acceptance Criteria

- [ ] All auth pages removed
- [ ] No broken imports/references
- [ ] Build succeeds

---

## Phase 10: Cognito Redirect Utilities (BAL-11.p10)

**Branch**: `BAL-11.p10`
**Target**: `main`
**Estimated Files**: 2 files
**Estimated Lines**: ~150 lines

### Changes

1. **Cognito redirect module**
   - File: `services/web/src/lib/auth/cognito.ts`
   - Functions:
     - `redirectToSignup(professionalId?)`
     - `redirectToLogin(professionalId?)`
     - `getCognitoAuthUrl(action, state)`

2. **Update existing auth hooks** (if needed)
   - File: `services/web/src/lib/auth/hooks.ts`
   - Use Cognito redirect instead of custom forms

### Acceptance Criteria

- [ ] Can redirect to Cognito signup
- [ ] Can redirect to Cognito login
- [ ] State parameter correctly encoded
- [ ] Uses environment variables for config

---

## Phase 11: Token Management in Frontend (BAL-11.p11)

**Branch**: `BAL-11.p11`
**Target**: `main`
**Estimated Files**: 2 files
**Estimated Lines**: ~200 lines

### Changes

1. **Token management module**
   - File: `services/web/src/lib/auth/token.ts`
   - Functions:
     - `getAccessToken()` - Get token, refresh if needed
     - `refreshAccessToken()` - Refresh using cookie
     - `clearAccessToken()` - Clear token
   - In-memory storage for access token
   - Automatic refresh 5 minutes before expiration

2. **Update existing token file** (if exists)
   - Merge with existing implementation

### Acceptance Criteria

- [ ] Access token stored in memory
- [ ] Automatic refresh before expiration
- [ ] Handles refresh failures
- [ ] Works with httpOnly cookie

---

## Phase 12: Update API Wrapper for Token Auth (BAL-11.p12)

**Branch**: `BAL-11.p12`
**Target**: `main`
**Estimated Files**: 2 files
**Estimated Lines**: ~150 lines

### Changes

1. **API wrapper update**
   - File: `services/web/src/lib/api/wrapper.ts`
   - Add Authorization header with Bearer token
   - Handle 401 responses with token refresh
   - Redirect to Cognito login on auth failure

2. **Journal API client update**
   - File: `services/web/src/lib/api/journal.ts`
   - Ensure uses authenticated fetch

### Acceptance Criteria

- [ ] API calls include Authorization header
- [ ] Automatically refreshes token on 401
- [ ] Redirects to login on auth failure
- [ ] All existing API calls work

---

## Phase 13: Route Protection (BAL-11.p13)

**Branch**: `BAL-11.p13`
**Target**: `main`
**Estimated Files**: 2 files
**Estimated Lines**: ~100 lines

### Changes

1. **Layout or hooks update**
   - File: `services/web/src/routes/+layout.svelte` or `src/hooks.ts`
   - Check for valid token on protected routes
   - Redirect to Cognito login if no token

2. **Auth check utility**
   - File: `services/web/src/lib/auth/hooks.ts` (update)
   - `checkAuthAndRedirect()` function

### Acceptance Criteria

- [ ] Protected routes require authentication
- [ ] Redirects to Cognito login if not authenticated
- [ ] Public routes (like /auth/callback) work without auth
- [ ] No infinite redirect loops

---

## Phase 14: Callback Page (Optional) (BAL-11.p14)

**Branch**: `BAL-11.p14`
**Target**: `main`
**Estimated Files**: 1 file
**Estimated Lines**: ~50 lines

### Changes

1. **Callback page** (if backend redirects to frontend)
   - File: `services/web/src/routes/auth/callback/+page.svelte`
   - Extract token from URL (if passed)
   - Store token in memory
   - Redirect to home or onboarding

### Acceptance Criteria

- [ ] Handles callback redirect from backend
- [ ] Stores token correctly
- [ ] Redirects to appropriate page

---

## Phase 15: Environment Variables & Configuration (BAL-11.p15)

**Branch**: `BAL-11.p15`
**Target**: `main`
**Estimated Files**: 3 files
**Estimated Lines**: ~100 lines

### Changes

1. **Backend config**
   - File: `services/journal/config/runtime.exs`
   - Add Cognito configuration variables

2. **Frontend env example**
   - File: `services/web/.env.example`
   - Add Cognito environment variables

3. **Documentation**
   - File: `services/journal/README.md`
   - Update with Cognito configuration instructions

### Acceptance Criteria

- [ ] All environment variables documented
- [ ] Config files updated
- [ ] README updated with setup instructions

---

## Summary

**Total Phases**: 15
**Total Estimated Files**: ~35 files
**Total Estimated Lines**: ~2,500 lines

### Phase Dependencies

```
p1 (Migrations) → p2 (Schemas)
p2 (Schemas) → p4 (Auth Context)
p3 (Cognito Client) → p4 (Auth Context)
p4 (Auth Context) → p5 (Callback)
p3 (Cognito Client) → p5 (Callback)
p3 (Cognito Client) → p6 (Refresh)
p7 (JWT Plug) → p8 (Router Integration)
p9 (Remove Pages) → p10 (Redirect Utils)
p10 (Redirect Utils) → p11 (Token Management)
p11 (Token Management) → p12 (API Wrapper)
p12 (API Wrapper) → p13 (Route Protection)
```

### Merge Strategy

- Each phase can be merged independently to `main`
- Phases should be merged in order (p1 → p2 → p3, etc.)
- Each PR should include tests
- Each PR should be reviewed before merge

### Testing Strategy

- **Unit tests**: Each module/function
- **Integration tests**: End-to-end flows (callback, refresh, token validation)
- **E2E tests**: Complete authentication flow

---

**Document Version**: 1.0
**Created**: 2025
**Status**: Ready for Implementation
