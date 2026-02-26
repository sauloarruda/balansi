#!/bin/bash

# Pre-commit hook to run RuboCop with autocorrect and prevent commits with lint errors

set -e

# Get the list of staged Ruby files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(rb|slim)$' || true)

if [ -z "$STAGED_FILES" ]; then
  exit 0
fi

# Run RuboCop with autocorrect on staged files
echo "Running RuboCop with autocorrect on staged Ruby files..."
bundle exec rubocop --autocorrect-all $STAGED_FILES || true

# Re-stage the corrected files
git add $STAGED_FILES

# Run RuboCop again to check if there are any remaining errors
echo "Checking for remaining RuboCop violations..."
if ! bundle exec rubocop $STAGED_FILES; then
  echo ""
  echo "❌ Lint errors found! Please fix them and try again."
  echo "You can also run: bundle exec rubocop --autocorrect-all"
  exit 1
fi

echo "✅ All Ruby files passed RuboCop checks!"
exit 0
