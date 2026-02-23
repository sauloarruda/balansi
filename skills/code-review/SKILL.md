---
name: code-review
description: Perform a structured engineering code review for a branch, commit range, or diff and generate actionable findings focused on bugs, regressions, security, performance, maintainability, and missing tests. Use when the user requests a review before commit or PR, asks for risk assessment on changed files, or needs a review artifact under doc/reviews/.
---

# Code Review

Review implementation changes with a staff-level quality bar and produce a concise, actionable artifact.

## Required Inputs

Provide or infer:
- Review scope (`main...HEAD`, specific commits, or selected files)
- Context label for output filename
- Optional product/phase context (ticket or plan section)

## Workflow

### 1. Collect Review Scope

Inspect changed files and commit diff.
Ignore unrelated generated files unless they impact runtime behavior.

### 2. Review By Risk Priority

Prioritize findings in this order:
1. Correctness bugs and behavioral regressions
2. Security and data exposure risks
3. Performance and scalability issues
4. Test coverage gaps on critical paths
5. Maintainability, duplication, and readability

### 3. Check Quality Dimensions

Evaluate:
- Input validation, auth/authz, injection, and unsafe data handling
- Query patterns (N+1), indexes, and algorithmic hotspots
- Error handling and logging quality
- Contract compatibility and migration safety
- Missing tests for happy path, failures, and boundaries
- Dead code, complexity, and SRP violations

### 4. Write Review Artifact

Create `doc/reviews/CR-<context>.md` with:
- Scope reviewed
- Findings ordered by severity (Critical, High, Medium, Low)
- File references and concrete remediation guidance
- Test gaps and recommended follow-ups

If no issues are found, write:
- `No blocking findings`
- Residual risk and untested areas

### 5. Wait For Feedback

Do not auto-commit or open PR from this skill.
Wait for user decision on which findings to apply.

## Review Style Rules

- Prefer specific, actionable recommendations over generic comments
- Reference concrete files and code locations for each issue
- Keep tone factual and concise
