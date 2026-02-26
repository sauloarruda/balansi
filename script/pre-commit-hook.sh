#!/bin/bash

# Pre-commit hook to run RuboCop with autocorrect and prevent commits with lint errors

set -e

# Get the list of staged Ruby files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.rb$' || true)

if [ -z "$STAGED_FILES" ]; then
  exit 0
fi

# Run RuboCop with autocorrect on staged files
echo "Running RuboCop with autocorrect on staged Ruby files..."
# Explicit error handling for RuboCop autocorrect
if ! bin/rubocop --autocorrect-all $STAGED_FILES; then
  AUTOCORRECT_EXIT_CODE=$?
  echo "⚠️  RuboCop autocorrect failed with exit code $AUTOCORRECT_EXIT_CODE."
  # If the error is not a standard lint violation (e.g., syntax error, file permission), exit with error
  # RuboCop returns 1 for offenses, 2 for errors (see: https://docs.rubocop.org/rubocop/usage/basic_usage.html#exit-codes)
  if [ $AUTOCORRECT_EXIT_CODE -eq 2 ]; then
    echo "❌ RuboCop encountered an error (syntax, file permissions, etc.). Aborting commit."
    exit 1
  else
    echo "Rubocop found and autocorrected offenses, continuing..."
  fi
fi

# WARNING: The following commands use $STAGED_FILES unquoted, which is unsafe if file names contain spaces or shell metacharacters.
# This can lead to command injection vulnerabilities. Consider quoting ("$STAGED_FILES") or using an array to safely handle file names.
# See: https://github.com/koalaman/shellcheck/wiki/SC2046
# Re-stage the corrected files
git add $STAGED_FILES

# Run RuboCop again to check if there are any remaining errors
echo "Checking for remaining RuboCop violations..."
if ! bin/rubocop $STAGED_FILES; then
  echo ""
  echo "❌ Lint errors found! Please fix them and try again."
  echo "You can also run: bin/rubocop --autocorrect-all"
  exit 1
fi

echo "✅ All Ruby files passed RuboCop checks!"
exit 0
