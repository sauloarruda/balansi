# Git Pre-Commit Hook - RuboCop Linting

## Overview

A git pre-commit hook is configured to automatically run RuboCop with autocorrect before each commit. This ensures:

1. **Autocorrect**: Lint issues are automatically fixed by RuboCop
2. **Re-staging**: Files corrected by RuboCop are re-added to the Git index
3. **Validation**: If issues remain after autocorrect, the commit is blocked

## How It Works

When you attempt to commit, the hook:

1. Identifies all staged Ruby (.rb) and Slim (.slim) files
2. Runs `rubocop --autocorrect-all` on those files
3. Re-adds the corrected files to the index
4. Runs `rubocop` again to validate there are no remaining offenses
5. If offenses still exist, the commit is blocked with a clear error message

## Manual Installation

If the hook is not installed for any reason, you can install it manually:

```bash
chmod +x script/pre-commit-hook.sh
cp script/pre-commit-hook.sh .git/hooks/pre-commit
```

Or run the setup script:

```bash
bin/setup
```

## Bypassing the Hook

If necessary, you can bypass the hook using the `--no-verify` flag:

```bash
git commit --no-verify
```

⚠️ Use with caution — this may allow lint issues to be committed.

## Manual Checks

To manually check and fix lint issues:

```bash
# Show all offenses
bundle exec rubocop

# Auto-correct offenses
bundle exec rubocop --autocorrect-all

# Check a single file
bundle exec rubocop app/models/user.rb
```

## Troubleshooting

### Hook is not running

Check whether the hook file is executable:

```bash
ls -la .git/hooks/pre-commit
```

If it is not executable, fix the permissions:

```bash
chmod +x .git/hooks/pre-commit
```

### RuboCop not found

Make sure project dependencies are installed:

```bash
bundle install
```

### Files are not being re-added

The hook assumes `git` is available and the repository is initialized. Verify the repository status:

```bash
git status
```
