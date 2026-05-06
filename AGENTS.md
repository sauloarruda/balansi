# Balansi

A nutrition and training journal. Users log meals and workouts via free text; the app calculates macros, calories, and provides daily scores.

## WHAT (Architecture)

- **Rails 8.1** / Ruby 3.4.7 / SQLite / Hotwire / Tailwind / Importmap / Slim views
- **Auth**: Rodauth via `app/misc/rodauth_main.rb` — server-rendered, no external OAuth
- **Service layer**: ActiveInteraction (`app/interactions/`) for business logic
- **Background jobs**: Solid Queue; caching via Solid Cache; WebSockets via Solid Cable
- **Deployment**: Kamal (`config/deploy.yml`, staging: `config/deploy.staging.yml`)

### Key Directories

| Path | Purpose |
|------|---------|
| `app/models/` | User, Patient, Professional, Journal, Meal, Exercise, PatientProfessionalAccess |
| `app/controllers/` | Journals, `patients/` (patient scope), `professionals/` (professional scope) |
| `app/interactions/` | ActiveInteraction service objects (auth, journal, patients, professionals) |
| `app/misc/` | Rodauth config (`rodauth_main.rb`) and Rodauth apps |
| `app/views/rodauth/` | Slim auth views |
| `spec/` | RSpec test suite |

### Domain Roles

- **Patient**: logs meals/exercises, views journal, manages professional access
- **Professional**: views and edits patient profiles, inspects patient journals

## WHY (Purpose)

Core loop: patient logs → AI parses free text → macros calculated → daily score + analysis.

Routes are scoped: `/patient/*` (patient self-service), `/professional/*` (professional dashboard), `/journals/:date` (journal CRUD).

## HOW (Workflows)

```bash
# Dev server
bin/dev

# Tests
bundle exec rspec
COV=1 bundle exec rspec  # with coverage

# Linting
bundle exec rubocop
bundle exec brakeman

# DB
bin/rails db:prepare
bin/rails db:migrate

# Deploy (staging)
bin/kamal deploy -d staging
```

### Dev Auth Shortcut

Append `?test_user_id=<id>` to any GET request in development to auto-sign-in as that user.

### Branch Naming

`{linear-issue-id}-{short-description}` — e.g. `BAL-42-add-meal-logging`

## Conventions

- Follow rubocop-rails-omakase style
- Use ActiveInteraction for any non-trivial business logic
- Use Rails i18n for all user-facing copy. Do not hardcode literal strings in views, controllers, services, or flashes; use `t(...)` / `I18n.t(...)` and update `config/locales/pt.yml` and `config/locales/en.yml` together.
- Slim templates (not ERB)
- Prefer Hotwire (Turbo Frames/Streams) over full-page renders for interactivity
- Test with RSpec + FactoryBot; system tests use Capybara

### Public Controllers (no auth)

For fully public entry points that must bypass `ApplicationController` authentication (e.g., invite landing pages), inherit from `ActionController::Base` directly — not `ApplicationController`. This avoids chaining `skip_before_action` calls against `authenticate_user!`, `ensure_current_patient!`, etc.

```ruby
class InvitesController < ActionController::Base
  def show
    # public action
  end
end
```

### Wildcard Route Ordering

Place catch-all / wildcard routes (e.g., `GET /:invite_code`) **last** in `routes.rb`, just before `root`. Use a regex constraint to prevent swallowing legitimate paths.
