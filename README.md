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
