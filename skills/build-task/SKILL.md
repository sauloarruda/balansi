---
name: build-task
description: Orchestrate implementation of one phase from an implementation plan end-to-end, including PRD/ERD readiness checks, branch setup, coding, verification, code review, PR creation, and plan updates. Use when the user asks to execute or continue work from doc/**/implementation-plan.md, wants the next incomplete phase implemented, or needs pre-implementation gap analysis from prd.md and erd.md.
---

# Build Task

Implement one phase of an implementation plan with explicit quality gates before merge.
Communicate in English.

## Required Inputs

Provide or infer:
- Implementation plan path (for example `doc/auth/implementation-plan.md`)
- PRD path (for example `doc/<module>/prd.md`)
- ERD path (for example `doc/<module>/erd.md`)
- Linear ticket ID (`BAL-XX`)
- Optional phase number
- Base branch (default: `main`)

If phase number is omitted, select the next incomplete phase from the plan.
Use the checklist in `references/readiness-checklist.md` during Step 0.

## Workflow

### 0. Run Pre-Implementation Readiness (PRD + ERD)

Read PRD and ERD before selecting a phase for coding.
Create the readiness artifact before implementation:
- `doc/reviews/READINESS-BAL-XX-pY.md`
- If phase is inferred and not numbered yet, use `doc/reviews/READINESS-BAL-XX-next.md`

Extract and validate:
- Functional scope, non-functional requirements, and explicit exclusions
- Data model constraints, relationships, and lifecycle assumptions
- API contracts, error handling expectations, and authorization boundaries
- Testability requirements and acceptance criteria quality

Produce a readiness checkpoint with:
- Missing or ambiguous requirements
- Contradictions between PRD, ERD, and implementation plan
- Required decisions still open
- Risks that can invalidate implementation effort
- A `GO` or `NO-GO` decision

Ask focused questions to close gaps and stop before coding until answers are received.
If user chooses to proceed with unresolved gaps, record assumptions explicitly in the phase notes.
Pause after generating the readiness artifact and wait for user approval to continue.

### 1. Select Scope

Read the plan and identify the target phase.
Extract:
- Acceptance criteria
- Expected files and estimated effort
- Dependencies or blockers

If the phase is already completed or blocked, stop and request user confirmation before continuing.
Do not continue to Step 2 when Step 0 result is `NO-GO`.

### 2. Prepare Branch

Start from latest mainline branch:
1. `git checkout <base-branch>`
2. `git pull origin <base-branch>`
3. Create phase branch from `<base-branch>` using ticket and phase

Use `BAL-XX.pY` as default naming. If the environment enforces prefixed branch names, use `codex/BAL-XX.pY`.

### 3. Implement Phase

Implement only the selected phase scope.
Follow project rules in `.cursor/rules/implementation.mdc`.

Apply these constraints:
- Reuse existing patterns before adding new abstractions
- Keep code simple and focused on current requirements
- Keep controllers thin: when an action accumulates non-trivial business logic, move it to an interaction (`ActiveInteraction`) under `app/interactions` and keep the controller focused on params, flow control, and rendering/redirects
- Add or update tests alongside implementation
- For any new or changed user-facing copy, use i18n and add/update keys in both `config/locales/pt.yml` and `config/locales/en.yml` (including controller flash/alert messages and views)
- For locale-sensitive inputs (especially dates), implement locale-specific display/input formats and server-side parsing rules for `pt` and `en`
- Respect Rails, security, performance, and migration standards

### 4. Verify Before Review

Run all relevant checks before requesting review:
1. Ensure code compiles/boots
2. Run lint/static checks (for this project, include RuboCop)
3. Run test suite and require full pass
4. If migrations changed, validate both `up` and `down` paths

If any check fails, fix issues before moving forward.

### 5. Produce Review Artifact

Invoke `$code-review` to review the current implementation diff and produce the review artifact.
If `$code-review` is unavailable, run an equivalent structured review manually with the same quality bar.

Write findings to `doc/reviews/CR-<context>.md` and wait for user feedback before committing.

### 6. Apply Feedback And Commit

Apply requested changes, then re-run verification.
After checks pass:
1. Stage changes
2. Commit with descriptive message referencing ticket and phase
3. Push branch

### 7. Create Pull Request

Invoke `$create-pr` to open the PR with project template and ticket context.
If `$create-pr` is unavailable, follow the same PR standards manually.

Share the PR link with the user.

### 8. Update Implementation Plan

Update the phase section in the plan:
- Mark phase as `✅ **Completed**`
- Check all acceptance criteria items (`- [x]`)
- Replace estimated files/lines with actuals when meaningfully different
- Note what changed versus original plan when applicable
- Record the next incomplete phase

### 9. Closeout

After PR creation and user confirmation, remove temporary review artifacts in `doc/reviews/` if no longer needed.
Provide a final summary with:
- What was implemented
- Validation executed
- PR URL
- Next phase to implement

## Non-Negotiable Gates

Require all of the following before final handoff:
- PRD/ERD readiness completed and open questions explicitly tracked
- Readiness artifact exists at `doc/reviews/READINESS-BAL-XX-pY.md` (or `...-next.md`)
- Build/boot succeeds
- Tests pass with no failures
- Migration rollback works (when migrations are part of the phase)
- No unresolved critical review findings
