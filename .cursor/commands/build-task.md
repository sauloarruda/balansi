# build-task

## Overview
This command implements a phase from an implementation plan. The user provides an implementation plan and optionally specifies which phase to develop. If no phase is specified, evaluate and select the next incomplete phase.

## Workflow

### Step 1: Branch Setup
Before starting implementation:
1. Run `git checkout main`
2. Run `git pull` to update main branch
3. Create a new branch from main following the pattern `BAL-XX.pY` where:
   - `XX` is the Linear issue ID
   - `Y` is the phase number

### Step 2: Implementation
1. Read and analyze the implementation plan to understand the phase requirements
2. Create all necessary files for the phase
3. Implement all required functionality
4. Ensure proper code organization and structure
5. Follow all rules in `@.cursor/rules/implementation.mdc` when writing code

### Step 3: Verification
Before proceeding, verify that:
1. **Code compiles**: Run the appropriate build/compile command for the service
2. **All tests pass**: Run the test suite and ensure 100% pass rate
3. **Migrations work**: If migrations exist, test both `up` and `down` operations:
   - Run migration up
   - Verify database state
   - Run migration down
   - Verify rollback works correctly

### Step 4: Code Review
1. Execute the `/code-review` command to generate a code review
2. Wait for the user to review the created files and the code review document
3. The user will provide feedback on review points

### Step 5: Apply Feedback and Commit
1. Apply all changes requested in the code review feedback
2. Re-verify that code compiles and tests pass after changes
3. Stage all changes: `git add .`
4. Create a commit with a descriptive message following project conventions
5. Push the branch: `git push origin BAL-XX.pY`

### Step 6: Create Pull Request
1. Execute the `/create-pr` command to create a GitHub PR for this phase
2. After the PR is created, delete the code review file (typically in `doc/reviews/`)

### Step 7: Update Implementation Plan
1. Read the implementation plan document (typically `doc/auth/implementation-plan.md` or similar)
2. Locate the completed phase section
3. Update the phase status to `✅ **Completed**` if not already marked
4. Check off all acceptance criteria items (`- [x]` instead of `- [ ]`)
5. Update the "Estimated Files" and "Estimated Lines" with actual values if significantly different
6. Add a brief note about what was actually implemented (if different from plan)
7. Identify and document the next incomplete phase number for future reference

### Step 8: User Review
The user will perform a final review and merge the PR on GitHub. No further action is required from the LLM at this stage.

## Notes
- Always work from the latest main branch
- Ensure all verification steps pass before proceeding to code review
- Follow project coding standards and conventions
- If any step fails, fix the issues before proceeding to the next step
