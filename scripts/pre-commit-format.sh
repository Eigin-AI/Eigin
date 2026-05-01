#!/usr/bin/env bash
# Pre-commit hook: lint staged Swift files with SwiftFormat.
# Install: ln -sf ../../scripts/pre-commit-format.sh .git/hooks/pre-commit

staged=$(git diff --cached --name-only --diff-filter=ACM -- '*.swift')
[ -z "$staged" ] && exit 0

if ! command -v swiftformat &>/dev/null; then
    echo "warning: swiftformat not found, skipping format check"
    exit 0
fi

echo "$staged" | xargs swiftformat --lint --quiet
if [ $? -ne 0 ]; then
    echo ""
    echo "Format violations found. Run 'make format' to fix."
    exit 1
fi
