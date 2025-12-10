# Implementation Plan — Cognito Hosted UI Authentication (BAL-11)

## Overview

This document outlines the implementation plan for migrating to Cognito Hosted UI authentication. Each phase is designed to be:
- **Small**: Maximum 5 files per PR
- **Focused**: Maximum 500 lines of changes per PR
- **Independent**: Can be merged directly to main
- **Testable**: Each phase includes tests

---

## Phase 1: Database Migrations (BAL-11.p1) ✅

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

## Phase 2: Elixir Schemas (BAL-11.p2) ✅

**Branch**: `BAL-11.p2`
**Target**: `main`
**Estimated Files**: 3 files
**Actual Files**: 5 files (including MealEntry update)
**Estimated Lines**: ~200 lines
**Actual Lines**: ~583 lines
**Status**: ✅ **Completed**

### Changes

1. **User schema**
   - File: `services/journal/lib/journal/auth/user.ex`
   - Schema with `name`, `email`, `cognito_id`
   - Changeset functions with comprehensive validation
   - Comment added explaining basic email validation (Cognito handles primary validation)

2. **Patient schema**
   - File: `services/journal/lib/journal/auth/patient.ex`
   - Schema with `user_id`, `professional_id`
   - Changeset functions
   - Added `belongs_to :user` association for better Ecto integration

3. **MealEntry schema update**
   - File: `services/journal/lib/journal/meals/meal_entry.ex`
   - Added `belongs_to :patient` association (replacing `field :patient_id`)

4. **Test files**
   - File: `services/journal/test/journal/auth/user_test.exs` (18 tests)
   - File: `services/journal/test/journal/auth/patient_test.exs` (10 tests)
   - Extracted helper function `unique_user_attrs/1` to reduce duplication

### Acceptance Criteria

- [x] User schema validates correctly
- [x] Patient schema validates correctly
- [x] All tests pass (238 tests, 0 failures)
- [x] Schemas can be inserted/updated via Repo

---

## Phase 3: Cognito Client Service (BAL-11.p3) ✅

**Branch**: `BAL-11.p3`
**Target**: `main`
**Estimated Files**: 2 files
**Actual Files**: 5 files (including config and documentation updates)
**Estimated Lines**: ~300 lines
**Actual Lines**: ~579 lines
**Status**: ✅ **Completed**

### Changes

1. **Cognito client module**
   - File: `services/journal/lib/journal/auth/cognito_client.ex`
   - Functions:
     - `exchange_code_for_tokens/2` - Exchange authorization code for tokens
     - `get_user_info/1` - Get user info from Cognito
     - `refresh_access_token/1` - Refresh access token
   - Uses HTTP client (Req) to call Cognito OAuth2 endpoints
   - Simplified implementation to work without client_secret (public client)

2. **Test file**
   - File: `services/journal/test/journal/auth/cognito_client_test.exs`
   - 12 comprehensive tests covering all functions and error scenarios
   - Mock Cognito responses using meck

3. **Configuration**
   - File: `services/journal/config/runtime.exs`
   - Added Cognito configuration reading from environment variables

4. **Documentation**
   - File: `services/journal/.env.example` - Added Cognito environment variables
   - File: `services/journal/README.md` - Updated with Cognito configuration documentation

### Acceptance Criteria

- [x] Can exchange code for tokens
- [x] Can get user info from access token
- [x] Can refresh access token
- [x] All tests pass with mocks (12 tests, 0 failures)
- [x] Manual testing performed with real Cognito endpoints

---

## Phase 4: Auth Context Module (BAL-11.p4) ✅

**Branch**: `BAL-11.p4`
**Target**: `main`
**Estimated Files**: 2 files
**Actual Files**: 5 files (including patient schema update, router comment, serverless.yml separation)
**Estimated Lines**: ~250 lines
**Actual Lines**: ~413 lines
**Status**: ✅ **Completed**

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
   - 14 comprehensive tests covering all functions and edge cases

3. **Patient schema improvement**
   - File: `services/journal/lib/journal/auth/patient.ex`
   - Added `foreign_key_constraint` for better error handling

4. **Infrastructure updates**
   - File: `services/journal/serverless.yml` - Separated Lambda functions (auth and journal)
   - File: `services/journal/lib/journal_web/router.ex` - Added comment for future auth routes

### Acceptance Criteria

- [x] Can create or find user
- [x] Can create patient record
- [x] Handles duplicate user creation gracefully
- [x] All tests pass (14 new tests, 264 total tests, 0 failures)

---

## Phase 5: Callback Controller (BAL-11.p5) ✅

**Branch**: `BAL-11.p5`
**Target**: `main`
**Estimated Files**: 2 files
**Actual Files**: 7 files (including Session module, tests, and documentation)
**Estimated Lines**: ~200 lines
**Actual Lines**: ~748 lines
**Status**: ✅ **Completed**

### Changes

1. **Callback controller**
   - File: `services/journal/lib/journal_web/controllers/auth_controller.ex`
   - Action: `callback/2`
   - Handles Cognito redirect with code and state
   - Creates user and patient records
   - Sets encrypted session cookie (refresh token encrypted before storage)
   - Redirects to frontend

2. **Session encryption module**
   - File: `services/journal/lib/journal/auth/session.ex`
   - Encrypts refresh token and user_id before storing in cookie
   - Uses `Plug.Crypto` for secure encryption/decryption
   - Follows same security pattern as Go auth service

3. **Router update**
   - File: `services/journal/lib/journal_web/router.ex`
   - Add route: `get "/auth/callback", AuthController, :callback`

4. **Test file**
   - File: `services/journal/test/journal_web/controllers/auth_controller_test.exs`
   - 9 comprehensive tests covering all scenarios and error cases

5. **Documentation and configuration**
   - File: `services/journal/README.md` - Added session encryption documentation
   - File: `services/journal/.env.example` - Added all required environment variables
   - File: `services/journal/Makefile` - Added `generate-session-secret` command

### Acceptance Criteria

- [x] Callback endpoint handles code exchange
- [x] Creates user and patient records
- [x] Sets httpOnly cookie with encrypted refresh token
- [x] Redirects to frontend URL
- [x] Handles errors gracefully
- [x] All tests pass (273 tests, 0 failures)

---

## Phase 6: Token Refresh Endpoint (BAL-11.p6) ✅

**Branch**: `BAL-11.p6`
**Target**: `main`
**Estimated Files**: 2 files
**Actual Files**: 3 files (including test file)
**Estimated Lines**: ~150 lines
**Actual Lines**: ~351 lines
**Status**: ✅ **Completed**
**PR**: [#17](https://github.com/sauloarruda/balansi/pull/17)

### Changes

1. **Auth controller - refresh action**
   - File: `services/journal/lib/journal_web/controllers/auth_controller.ex`
   - Action: `refresh/2`
   - Reads refresh token from encrypted session cookie
   - Calls Cognito to refresh access token
   - Returns new access token with expiration time
   - Comprehensive error handling for all scenarios

2. **Router update**
   - File: `services/journal/lib/journal_web/router.ex`
   - Add route: `post "/auth/refresh", AuthController, :refresh`

3. **Test file**
   - File: `services/journal/test/journal_web/controllers/auth_controller_test.exs`
   - 7 comprehensive tests covering all scenarios and error cases

### Acceptance Criteria

- [x] Refresh endpoint reads cookie
- [x] Returns new access token
- [x] Handles invalid refresh token
- [x] Returns correct expiration time

---

## Phase 7: JWT Validation Plug (BAL-11.p7) ✅

**Branch**: `BAL-11.p7`
**Target**: `main`
**Estimated Files**: 2 files
**Actual Files**: 6 files (including tests and fixes)
**Estimated Lines**: ~400 lines
**Actual Lines**: ~600+ lines
**Status**: ✅ **Completed**
**PR**: [#18](https://github.com/sauloarruda/balansi/pull/18)

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

3. **User name extraction fixes**
   - File: `services/journal/lib/journal_web/controllers/auth_controller.ex`
   - Extract name from `preferred_username`, then `name`, fallback to `email`
   - Merge ID token claims with user_info for complete user profile
   - Decode ID token to access additional user attributes

4. **Patient creation fix**
   - File: `services/journal/lib/journal/auth.ex`
   - Add `create_or_find_patient/2` to prevent duplicate patient creation
   - Handle existing patients gracefully during callback

5. **Tests**
   - File: `services/journal/test/journal_web/plugs/verify_token_test.exs`
   - File: `services/journal/test/journal/auth/jwks_test.exs`
   - File: `services/journal/test/journal_web/controllers/auth_controller_test.exs`
   - Comprehensive test coverage for all scenarios

6. **Documentation**
   - File: `doc/auth/erd.md`
   - Updated Cognito auth URL to include `profile` scope

### Acceptance Criteria

- [x] Validates JWT token signature
- [x] Extracts cognito_id correctly
- [x] Looks up user in database
- [x] Gets patient_id correctly
- [x] Handles invalid/expired tokens
- [x] Caches JWKS keys
- [x] Extracts user name correctly from Cognito tokens
- [x] Handles duplicate patient creation

---

## Phase 8: Integrate JWT Plug in Router (BAL-11.p8) ✅

**Branch**: `BAL-11.p8`
**Target**: `main`
**Estimated Files**: 2 files
**Actual Files**: 6 files (including test infrastructure updates)
**Estimated Lines**: ~50 lines
**Actual Lines**: ~272 lines (net: ~207 lines)
**Status**: ✅ **Completed**
**PR**: [#19](https://github.com/sauloarruda/balansi/pull/19)

### Changes

1. **Router - protected pipeline**
   - File: `services/journal/lib/journal_web/router.ex`
   - Create `:protected` pipeline with `VerifyToken` plug
   - Apply to meal routes

2. **Meal controller update**
   - File: `services/journal/lib/journal_web/controllers/meal_controller.ex`
   - Remove `@poc_patient_id` constant
   - Use `conn.assigns[:current_patient_id]` instead

3. **Test infrastructure**
   - File: `services/journal/test/support/conn_case.ex`
   - Added `authenticate_conn/2` helper for test setup with JWT tokens
   - Generates valid JWT tokens and mocks JWKS for testing

4. **Test updates**
   - File: `services/journal/test/journal_web/controllers/meal_controller_test.exs`
   - Updated all tests to use authenticated connections
   - File: `services/journal/test/journal_web/meal_helpers_test.exs`
   - Updated helper tests to authenticate before requests
   - File: `services/journal/test/support/meal_helpers.ex`
   - Updated macros to support dynamic patient_id
   - Fixed `ensure_patient_exists` to use Ecto insert_all

### Acceptance Criteria

- [x] Protected routes require valid JWT token
- [x] Meal controller uses patient_id from token
- [x] Returns 401 for invalid/missing tokens
- [x] All existing tests updated and passing (307 tests, 0 failures)

---

## Phase 9: Remove Frontend Auth Pages (BAL-11.p9) ✅

**Branch**: `BAL-11.p9`
**Target**: `main`
**Estimated Files**: 5 files
**Actual Files**: 12 files (including i18n cleanup)
**Estimated Lines**: ~50 lines (deletions)
**Actual Lines**: ~1,495 deletions, 17 insertions
**Status**: ✅ **Completed**
**PR**: [#20](https://github.com/sauloarruda/balansi/pull/20)

### Changes

1. **Delete auth pages**
   - File: `services/web/src/routes/auth/+page.svelte` ✅
   - File: `services/web/src/routes/auth/confirmation/+page.svelte` ✅
   - File: `services/web/src/routes/auth/forgot-password/+page.svelte` ✅
   - File: `services/web/src/routes/auth/reset-password/+page.svelte` ✅
   - File: `services/web/tests/signup.spec.ts` ✅

2. **Remove unused i18n entries**
   - Removed `auth.signup.*` entries from en.json and pt.json
   - Removed `auth.confirmation.*` entries
   - Removed `auth.forgotPassword.*` entries
   - Removed `auth.resetPassword.*` entries (including requirements)
   - Kept `auth.logout` as it's still used

3. **Update error handling**
   - Updated `errorCodes.ts` to remove auth-related error codes
   - Updated `wrapper.ts` and `journal.ts` to use generic error messages
   - Removed unused `getPasswordErrors` function from `validation.ts`

4. **Update main page**
   - Added TODO comments for phase 10 (Cognito redirect)

### Acceptance Criteria

- [x] All auth pages removed
- [x] No broken imports/references
- [x] Build succeeds
- [x] Unused i18n entries removed

---

## Phase 10: Cognito Redirect Utilities (BAL-11.p10) ✅

**Branch**: `BAL-11.p10`
**Target**: `main`
**Estimated Files**: 2 files
**Actual Files**: 5 files (including .env.example, Makefile, README updates)
**Estimated Lines**: ~150 lines
**Actual Lines**: ~179 lines
**Status**: ✅ **Completed**
**PR**: [#21](https://github.com/sauloarruda/balansi/pull/21)

### Changes

1. **Cognito redirect module**
   - File: `services/web/src/lib/auth/cognito.ts`
   - Functions:
     - `redirectToSignup(professionalId?)` - Redirects to Cognito signup
     - `redirectToLogin(professionalId?)` - Redirects to Cognito login
     - `getCognitoAuthUrl(action, state)` - Builds Cognito URLs with proper encoding
   - Includes environment variable validation
   - Proper state parameter encoding using URLSearchParams

2. **Update main page**
   - File: `services/web/src/routes/+page.svelte`
   - Replaced TODO comments with actual Cognito redirects
   - Uses `redirectToLogin()` for unauthenticated users and after logout

3. **Environment configuration**
   - File: `services/web/.env.example` - Added Cognito environment variables template
   - File: `services/web/Makefile` - Updated `dev` target to automatically load `.env` file
   - File: `services/web/README.md` - Added comprehensive Cognito configuration instructions

### Acceptance Criteria

- [x] Can redirect to Cognito signup
- [x] Can redirect to Cognito login
- [x] State parameter correctly encoded
- [x] Uses environment variables for config

---

## Phase 11: Token Management in Frontend (BAL-11.p11) ✅

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

## Phase 12: Update OpenAPI Specification with Auth Endpoints (BAL-11.p12) ✅

**Branch**: `BAL-11.p12`
**Target**: `main`
**Estimated Files**: 1 file
**Actual Files**: 1 file
**Estimated Lines**: ~200 lines
**Actual Lines**: ~349 insertions, 84 deletions (net: +265 lines)
**Status**: ✅ **Completed**
**PR**: [#23](https://github.com/sauloarruda/balansi/pull/23)

### Changes

1. **OpenAPI specification update**
   - File: `services/journal/openapi.yaml`
   - Add `/auth/callback` endpoint (GET)
     - Query parameters: `code` (required), `state` (optional)
     - Responses: 302 (redirect), 400 (missing code), 500 (server error)
     - Comprehensive flow documentation with 7-step process
     - Header documentation (Location, Set-Cookie)
   - Add `/auth/refresh` endpoint (POST)
     - Uses httpOnly cookie (`bal_session_id`) for refresh token
     - Responses: 200 (success with access_token, expires_in, token_type), 401 (invalid session), 500 (server error)
     - Uses `CookieAuth` security scheme
   - Add `RefreshTokenResponse` schema
     - Defines response format matching backend (snake_case)
   - Update security schemes
     - Enhanced `BearerAuth` description with JWT validation details
     - Added `CookieAuth` scheme for cookie-based authentication
   - Apply security requirements to protected endpoints
     - All meal endpoints now specify `BearerAuth` requirement

### Acceptance Criteria

- [x] `/auth/callback` endpoint documented with all parameters and responses
- [x] `/auth/refresh` endpoint documented with cookie-based authentication
- [x] Security schemes properly documented
- [x] All existing endpoints remain documented
- [x] OpenAPI spec validates successfully

---

## Phase 13: Remove Go API Access from Frontend (BAL-11.p13)

**Branch**: `BAL-11.p13`
**Target**: `main`
**Estimated Files**: 5-8 files
**Estimated Lines**: ~300 lines (deletions)

### Changes

1. **Remove Go API wrapper**
   - File: `services/web/src/lib/api/wrapper.ts`
   - Remove `AuthenticationApi` import and usage
   - Remove `authApiInstance` and `api.auth` export
   - Keep only the generic fetch wrapper for Journal API
   - Remove references to Go auth service

2. **Remove Go API client usage**
   - File: `services/web/src/lib/auth/clientAuth.ts`
   - Remove `api.auth.logout()` call
   - Update logout to only clear local token and redirect

3. **Update package.json**
   - File: `services/web/package.json`
   - Remove `generate:api` script that generates from Go OpenAPI
   - Remove dependency on Go auth service OpenAPI spec

4. **Remove generated API client**
   - File: `services/web/src/lib/api/generated/` (entire directory)
   - Delete all generated TypeScript files from Go OpenAPI spec

5. **Update playwright config**
   - File: `services/web/playwright.config.ts`
   - Remove Go auth service startup from test setup

6. **Update README**
   - File: `services/web/README.md`
   - Remove all references to Go auth service
   - Remove instructions for deploying/configuring Go auth service

### Acceptance Criteria

- [ ] No imports or references to `AuthenticationApi` or Go auth service
- [ ] No generated API client files from Go OpenAPI
- [ ] Frontend no longer calls Go auth endpoints
- [ ] Build succeeds without Go auth service dependencies
- [ ] All references to Go auth service removed from documentation

---

## Phase 14: Migrate Frontend to Use Elixir Journal API (BAL-11.p14)

**Branch**: `BAL-11.p14`
**Target**: `main`
**Estimated Files**: 3-5 files
**Estimated Lines**: ~200 lines

### Changes

1. **Update API base URL configuration**
   - File: `services/web/src/lib/api/wrapper.ts`
   - Update `getApiBaseUrl()` to point to Journal API (Elixir) instead of Go auth service
   - Ensure all API calls use Journal API base URL

2. **Update Journal API client**
   - File: `services/web/src/lib/api/journal.ts`
   - Ensure `getJournalApiUrl()` uses correct Elixir API URL
   - Verify all endpoints match Elixir routes (`/journal/meals`, etc.)
   - Update to use unified API base URL if applicable

3. **Update token refresh**
   - File: `services/web/src/lib/auth/token.ts`
   - Ensure `refreshAccessToken()` calls Elixir `/journal/auth/refresh` endpoint
   - Verify response format matches Elixir API (snake_case: `access_token`, `expires_in`)

4. **Update environment variables**
   - File: `services/web/.env.example`
   - Update `VITE_API_URL` to point to Journal API (Elixir)
   - Remove `VITE_JOURNAL_API_URL` if no longer needed (or keep if separate)
   - Update documentation for new API URL

5. **Update README**
   - File: `services/web/README.md`
   - Update API configuration instructions to reference Elixir Journal API
   - Remove any remaining Go auth service references

### Acceptance Criteria

- [ ] All API calls go to Elixir Journal API
- [ ] Token refresh uses Elixir `/journal/auth/refresh` endpoint
- [ ] All meal endpoints work with Elixir API
- [ ] Environment variables point to correct services
- [ ] Documentation updated

---

## Phase 15: Remove Go Auth Service from Codebase (BAL-11.p15)

**Branch**: `BAL-11.p15`
**Target**: `main`
**Estimated Files**: Entire `services/auth` directory
**Estimated Lines**: ~10,000+ lines (deletions)

### Changes

1. **Delete Go auth service directory**
   - Directory: `services/auth/`
   - Remove entire service including:
     - All Go source files
     - OpenAPI specification
     - Serverless configuration
     - Migrations
     - Tests
     - Documentation

2. **Update root documentation**
   - Check for references in:
     - `README.md` (root)
     - `doc/` directory
     - Any architecture diagrams
     - Deployment documentation

3. **Update CI/CD configurations**
   - Remove Go auth service from:
     - GitHub Actions workflows
     - Deployment scripts
     - Infrastructure as Code (if applicable)

4. **Update dependencies**
   - Remove Go-related dependencies if no other Go services exist
   - Update Dockerfiles if they reference auth service

### Acceptance Criteria

- [ ] `services/auth/` directory completely removed
- [ ] No references to Go auth service in documentation
- [ ] No references in CI/CD configurations
- [ ] No broken links or imports
- [ ] All documentation updated to reflect Elixir-only architecture

---

## Summary

**Total Phases**: 15
**Total Estimated Files**: ~45 files
**Total Estimated Lines**: ~3,000 lines (including deletions)

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
p11 (Token Management) → p12 (OpenAPI Update)
p5 (Callback) → p12 (OpenAPI Update)
p6 (Refresh) → p12 (OpenAPI Update)
p12 (OpenAPI Update) → p13 (Remove Go API)
p13 (Remove Go API) → p14 (Migrate to Elixir API)
p14 (Migrate to Elixir API) → p15 (Remove Go Service)
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

**Document Version**: 2.0
**Created**: 2025
**Last Updated**: 2025-01-27
**Status**: In Progress (Phases 1-12 completed, Phases 13-15 pending)

### Recent Updates (v2.0)

- **Phase 12**: Changed from "Update API Wrapper" to "Update OpenAPI Specification with Auth Endpoints"
- **Phase 13**: Changed from "Route Protection" to "Remove Go API Access from Frontend"
- **Phase 14**: Changed from "Callback Page" to "Migrate Frontend to Use Elixir Journal API"
- **Phase 15**: Changed from "Environment Variables" to "Remove Go Auth Service from Codebase"
- Added migration path to remove Go auth service and consolidate on Elixir Journal API
