# create-pr

Create a pull request for the current branch with proper context and formatting.

## Prerequisites

1. **Linear Ticket ID**: Identify the Linear ticket ID in format `BAL-XX` (where XX is a number).
   - If no ticket ID is provided, ask the user for it.
   - The ticket ID is required for the PR title and context.

## Branch Management

2. **Verify Branch Name**: Check if the current branch name matches the ticket ID (e.g., `BAL-XX`).
   - If the branch doesn't match the ticket ID, create a new branch from `main` with the ticket ID as the branch name.
   - If the branch already matches, proceed with the current branch.

## Pull Request Creation

3. **Create PR on GitHub**:
   - Source branch: current branch
   - Base branch: `main` (or as specified by the user)

4. **PR Title Format**: `BAL-XX: {description of what was implemented}`
   - Where `BAL-XX` is the Linear ticket ID
   - Description should be concise and describe the main changes

5. **PR Description**:
   - Use the PR template from `.github/PULL_REQUEST_TEMPLATE.md`
   - Gather context from:
     - Linear ticket description (use GitHub MCP tools to search or fetch ticket details)
     - Documentation files in `doc/{module_name}/`:
       - `prd.md` - Product Requirements Document
       - `erd.md` - Entity Relationship Diagram
     - Use these documents to understand what part of the system is being implemented
   - Include relevant context about the changes and their purpose

6. **Additional Instructions**: Consider any additional instructions or requirements provided by the user.

## Execution Steps

1. Get Linear ticket ID (ask user if not provided)
2. Verify/update branch name to match ticket ID
3. Read PR template
4. Read relevant documentation files from `doc/` directory
5. Get Linear ticket description
6. Draft PR description using template and context
7. Create PR with proper title and description
8. Confirm PR creation with user and show a clickable link
