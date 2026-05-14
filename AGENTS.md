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
- Write all project documentation, commit messages, pull request titles, and pull request descriptions in English. This applies even when the conversation or implementation notes are in another language.
- Use ActiveInteraction for any non-trivial business logic. Keep controllers thin: they should handle HTTP concerns such as authentication context, params, redirects/renders, status codes, and response serialization. Move filtering/search rules, persistence workflows, authorization-adjacent scoping, AI orchestration, calculations, and multi-step decisions into `app/interactions/` before adding or expanding controller actions. Prefer adding focused interaction specs instead of burying this behavior in controller/request specs only.
- Wrap any operation that creates or updates more than one model in a database transaction so the local persistence changes are atomic. This applies in interactions, background jobs, controllers, and service objects.
- Always scope queries for models that have `patient_id` or `user_id` through the current authenticated owner before fetching records. Prefer association-scoped lookups such as `current_patient.recipes.find(params[:id])`, `current_user.records.find(...)`, or explicit filters like `Recipe.where(patient_id: current_patient.id, id: ids)`. Never resolve these records by global `id` alone, including in helpers, interactions, background jobs, JSON endpoints, and view support code; professional access flows must use their existing patient authorization scope.
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

<!-- rtk-instructions v2 -->
# RTK (Rust Token Killer) - Token-Optimized Commands

## Golden Rule

**Always prefix commands with `rtk`**. If RTK has a dedicated filter, it uses it. If not, it passes through unchanged. This means RTK is always safe to use.

**Important**: Even in command chains with `&&`, use `rtk`:
```bash
# ❌ Wrong
git add . && git commit -m "msg" && git push

# ✅ Correct
rtk git add . && rtk git commit -m "msg" && rtk git push
```

## RTK Commands by Workflow

### Build & Compile (80-90% savings)
```bash
rtk cargo build         # Cargo build output
rtk cargo check         # Cargo check output
rtk cargo clippy        # Clippy warnings grouped by file (80%)
rtk tsc                 # TypeScript errors grouped by file/code (83%)
rtk lint                # ESLint/Biome violations grouped (84%)
rtk prettier --check    # Files needing format only (70%)
rtk next build          # Next.js build with route metrics (87%)
```

### Test (90-99% savings)
```bash
rtk cargo test          # Cargo test failures only (90%)
rtk vitest run          # Vitest failures only (99.5%)
rtk playwright test     # Playwright failures only (94%)
rtk test <cmd>          # Generic test wrapper - failures only
```

### Git (59-80% savings)
```bash
rtk git status          # Compact status
rtk git log             # Compact log (works with all git flags)
rtk git diff            # Compact diff (80%)
rtk git show            # Compact show (80%)
rtk git add             # Ultra-compact confirmations (59%)
rtk git commit          # Ultra-compact confirmations (59%)
rtk git push            # Ultra-compact confirmations
rtk git pull            # Ultra-compact confirmations
rtk git branch          # Compact branch list
rtk git fetch           # Compact fetch
rtk git stash           # Compact stash
rtk git worktree        # Compact worktree
```

Note: Git passthrough works for ALL subcommands, even those not explicitly listed.

### GitHub (26-87% savings)
```bash
rtk gh pr view <num>    # Compact PR view (87%)
rtk gh pr checks        # Compact PR checks (79%)
rtk gh run list         # Compact workflow runs (82%)
rtk gh issue list       # Compact issue list (80%)
rtk gh api              # Compact API responses (26%)
```

### JavaScript/TypeScript Tooling (70-90% savings)
```bash
rtk pnpm list           # Compact dependency tree (70%)
rtk pnpm outdated       # Compact outdated packages (80%)
rtk pnpm install        # Compact install output (90%)
rtk npm run <script>    # Compact npm script output
rtk npx <cmd>           # Compact npx command output
rtk prisma              # Prisma without ASCII art (88%)
```

### Files & Search (60-75% savings)
```bash
rtk ls <path>           # Tree format, compact (65%)
rtk read <file>         # Code reading with filtering (60%)
rtk grep <pattern>      # Search grouped by file (75%)
rtk find <pattern>      # Find grouped by directory (70%)
```

### Analysis & Debug (70-90% savings)
```bash
rtk err <cmd>           # Filter errors only from any command
rtk log <file>          # Deduplicated logs with counts
rtk json <file>         # JSON structure without values
rtk deps                # Dependency overview
rtk env                 # Environment variables compact
rtk summary <cmd>       # Smart summary of command output
rtk diff                # Ultra-compact diffs
```

### Infrastructure (85% savings)
```bash
rtk docker ps           # Compact container list
rtk docker images       # Compact image list
rtk docker logs <c>     # Deduplicated logs
rtk kubectl get         # Compact resource list
rtk kubectl logs        # Deduplicated pod logs
```

### Network (65-70% savings)
```bash
rtk curl <url>          # Compact HTTP responses (70%)
rtk wget <url>          # Compact download output (65%)
```

### Meta Commands
```bash
rtk gain                # View token savings statistics
rtk gain --history      # View command history with savings
rtk discover            # Analyze Claude Code sessions for missed RTK usage
rtk proxy <cmd>         # Run command without filtering (for debugging)
rtk init                # Add RTK instructions to CLAUDE.md
rtk init --global       # Add RTK to ~/.claude/CLAUDE.md
```

## Token Savings Overview

| Category | Commands | Typical Savings |
|----------|----------|-----------------|
| Tests | vitest, playwright, cargo test | 90-99% |
| Build | next, tsc, lint, prettier | 70-87% |
| Git | status, log, diff, add, commit | 59-80% |
| GitHub | gh pr, gh run, gh issue | 26-87% |
| Package Managers | pnpm, npm, npx | 70-90% |
| Files | ls, read, grep, find | 60-75% |
| Infrastructure | docker, kubectl | 85% |
| Network | curl, wget | 65-70% |

Overall average: **60-90% token reduction** on common development operations.
<!-- /rtk-instructions -->
