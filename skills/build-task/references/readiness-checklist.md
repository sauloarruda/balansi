# Readiness Checklist

Use this checklist before any implementation phase.
Write the output to:
- `doc/reviews/READINESS-BAL-XX-pY.md`
- or `doc/reviews/READINESS-BAL-XX-next.md` when phase number is not fixed

## Required Output Structure

Use exactly these sections:

1. Scope For This Phase
- In scope
- Out of scope
- Dependencies

2. PRD Gaps
- Missing acceptance criteria
- Ambiguous functional requirements
- Missing non-functional requirements

3. ERD Gaps
- Missing entities, fields, constraints, or indexes
- Relationship ambiguity
- Data lifecycle ambiguity (create/update/delete/archive)

4. PRD x ERD x Plan Contradictions
- Contradiction description
- Affected files/components
- Why it blocks or risks implementation

5. Open Questions (Must Ask User)
- Question
- Why it matters
- Blocking status (`Blocking` or `Non-blocking`)

6. Assumptions (If Proceeding Without Answers)
- Assumption statement
- Impact if wrong
- Owner approval status

7. Readiness Decision
- Decision: `GO` or `NO-GO`
- Blocking items still open
- Conditions to move from `NO-GO` to `GO`

## Decision Rule

Set decision to `NO-GO` when any blocking item is unresolved.
Set decision to `GO` only when blocking items are resolved or explicitly approved as assumptions.

## Question Quality Rules

- Ask concrete, answerable questions.
- Avoid combining multiple decisions in one question.
- Link each question to a specific risk or acceptance criterion.
- Prioritize questions that can change architecture, schema, or API contracts.
