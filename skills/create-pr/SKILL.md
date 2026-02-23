---
name: create-pr
description: Create a GitHub pull request from the current branch with proper title, body, and ticket context. Use when implementation is complete and validated, when the user asks to open a PR for a BAL-XX ticket, or when a phase workflow requires PR creation based on .github/PULL_REQUEST_TEMPLATE.md and project docs.
---

# Create Pr

Create PRs with consistent formatting, complete context, and traceability to ticket and phase.

## Required Inputs

Provide or infer:
- Ticket ID in format `BAL-XX`
- Base branch (default: `main`)
- Source branch (default: current branch)
- High-level summary of implemented scope

If ticket ID is missing, request it before continuing.

## Workflow

### 1. Validate Branch And Ticket

Check current branch and confirm it maps to the ticket.
If branch naming is inconsistent, align branch strategy with user preference before creating PR.

### 2. Gather Context

Read:
- `.github/PULL_REQUEST_TEMPLATE.md`
- Relevant implementation plan section
- `doc/<module>/prd.md` and `doc/<module>/erd.md` when available
- Ticket description (via available integrations)

Extract objective, scope, risks, migrations, and test evidence.

### 3. Build PR Title And Description

Use title format:
- `BAL-XX: <implemented scope>`

Populate template with:
- What changed
- Why it changed
- How it was validated
- Migration or rollback notes
- Follow-up items and known limitations

### 4. Create Pull Request

Open PR from source to base branch using project standard tooling.
Return PR URL and summary of final title/body.

### 5. Confirm And Handoff

Confirm PR is open and ready for reviewer.
List any manual actions still required.

## Output Rules

- Keep title concise and specific
- Keep description factual and complete
- Never omit validation evidence when tests were executed
