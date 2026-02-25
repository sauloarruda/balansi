---
name: code-review
description: Perform a structured engineering code review for a branch, commit range, or diff and generate actionable findings focused on bugs, regressions, security, performance, maintainability, and missing tests. Use when the user requests a review before commit or PR, asks for risk assessment on changed files, or needs a review artifact under doc/reviews/.
---
Compatibility alias for the Codex skill.

Single source of truth:
- `skills/code-review/SKILL.md`

Execution:
- Invoke `$code-review` and follow the skill workflow.

### Local auth bypass for verification

When reproducing or testing auth-protected flows locally, start the dev server and append `?test_user_id=<id>` to the target GET path. The [Development test users](README.md#development-test-users-ai-testing) section explains how to obtain a development user ID and how the [Authentication concern](app/controllers/concerns/authentication.rb#L1-L60) honors the parameter during development-only runs.
