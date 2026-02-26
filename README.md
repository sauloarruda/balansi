# Balansi

A fast, lightweight, feedback-oriented nutrition and training journal. Users log meals and workouts using free-text descriptions, and the app automatically calculates macros, calories, and provides daily scores with analysis.

## About v1

v1 focuses on **log**, **calculate**, and **evaluate**. The goal is to create an "evaluative daily journal" that users can complete in seconds and trust. See [`doc/PITCH-v1.md`](doc/PITCH-v1.md) for the complete vision and scope.

## Technologies

- **Ruby on Rails 8.1** - Web framework
- **PostgreSQL** - Database
- **AWS Cognito** - Authentication (Hosted UI)
- **Terraform** - Infrastructure as Code
- **Stimulus** - JavaScript framework
- **RSpec** - Testing framework

## Setup

### Prerequisites

- Ruby 3.4.5
- PostgreSQL 17

### Installation

1. **Install dependencies:**
   ```bash
   bundle install
   ```

2. **Set up database:**
   ```bash
   bin/rails db:prepare
   ```
   This creates the database, loads the schema, and runs migrations.

3. **Run the application:**
   ```bash
   bin/dev
   ```

Or use the setup script:
```bash
bin/setup
```

**Note**: Infrastructure setup (Terraform) and Rails credentials configuration are only needed once. See [`terraform/README.md`](terraform/README.md) for initial infrastructure setup.

## Documentation

- **Product Vision**: [`doc/PITCH-v1.md`](doc/PITCH-v1.md) - Product pitch and v1 scope
- **Authentication PRD**: [`doc/auth/prd.md`](doc/auth/prd.md) - Authentication module requirements
- **Authentication ERD**: [`doc/auth/erd.md`](doc/auth/erd.md) - Authentication architecture and data model
- **Infrastructure**: [`terraform/README.md`](terraform/README.md) - Terraform setup and Cognito configuration

## Kamal Secrets

Use the template in `/Users/sauloarruda/Developer/balansi/.kamal/secrets.example` and keep real secrets only in your local `.kamal/secrets`:

```bash
cp .kamal/secrets.example .kamal/secrets
```

Required values:
- `RAILS_MASTER_KEY`
- `KAMAL_REGISTRY_PASSWORD`
- `DATABASE_URL`
- `CACHE_DATABASE_URL`
- `QUEUE_DATABASE_URL`
- `CABLE_DATABASE_URL`

Safer approach:
- do not hardcode plaintext values in `.kamal/secrets`
- fetch secrets dynamically from AWS Secrets Manager and ECR (see template)
- use AWS SSO/MFA locally so tokens are short-lived

The project is configured to ignore `.kamal/secrets` in git, so only `.kamal/secrets.example` should be committed.

## Kamal Environments

Kamal is split by environment config files:
- Base/default: `/Users/sauloarruda/Developer/balansi/config/deploy.yml`
- Staging: `/Users/sauloarruda/Developer/balansi/config/deploy.staging.yml`

Run staging with destination flag:

```bash
bin/kamal deploy -d staging
```

Useful staging commands:

```bash
bin/kamal setup -d staging
bin/kamal logs -d staging
bin/kamal app exec -d staging --interactive "bin/rails db:prepare"
```

## Testing

Run the test suite:
```bash
bundle exec rspec
```

Enable code coverage:
```bash
COV=1 bundle exec rspec
```

See the current README for detailed testing instructions.

### Development test users (AI testing)

When an AI-powered run or manual exploration needs to exercise authenticated routes without navigating the Cognito hosted UI, start the app locally (`bin/dev`). Append `?test_user_id=<id>` to any GET URL and the [Authentication concern](app/controllers/concerns/authentication.rb#L1-L60) intercepts that parameter in development, loads the matching user, clears the query parameter, and redirects back so the rest of your session runs against that account.

Steps to use it safely:
1. Find a user ID from the development database (for example, `bin/rails runner "puts User.first.id"` or inspect `db/seeds/development.rb`).
2. Visit `http://localhost:4000/<protected_path>?test_user_id=<id>`; the user will be signed in for that request and redirected without the parameter.
3. If the ID does not exist the concern redirects to `/auth/sign_in` with an alert that includes the missing ID.
4. The bypass runs only when `Rails.env.development?` and on GET requests. It also clears `session[:refresh_token]` so you start with a clean session.

Use this shortcut for AI or automation tests that need authenticated context; do not expose `test_user_id` in staging/production.
