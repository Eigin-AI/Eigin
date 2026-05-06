#!/usr/bin/env bash
# Commit-msg hook: validate commit message follows Conventional Commits format.
# https://www.conventionalcommits.org/

commit_msg_file="$1"

if [ -z "$commit_msg_file" ] || [ ! -f "$commit_msg_file" ]; then
    echo "error: commit-msg hook: no commit message file found" >&2
    exit 1
fi

commit_msg=$(cat "$commit_msg_file")

# Remove comment lines (git default comment char is #)
comment_char=$(git config core.commentChar 2>/dev/null || echo '#')
commit_msg=$(printf '%s\n' "$commit_msg" | grep -v "^${comment_char}")

# Header is the first non-empty line
header=$(printf '%s\n' "$commit_msg" | grep -v '^$' | head -1)

if [ -z "$header" ]; then
    echo "error: commit-msg hook: commit message is empty" >&2
    echo "" >&2
    echo "Conventional Commits format:" >&2
    echo "  <type>(<scope>): <description>" >&2
    echo "" >&2
    echo "  types: build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test" >&2
    echo "  example: feat(chat): add dictation stream view" >&2
    exit 1
fi

# Validate header against Conventional Commits regex (POSIX compatible)
# From: https://gist.github.com/marcojahn/482410b728c31b221b70ea6d2c433f0c
if ! printf '%s\n' "$header" | grep -qE '^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test){1}(\([[:alnum:]._-]+\))?(!)?: ([[:alnum:]])+([[:space:][:print:]]*)'; then
    echo "error: commit-msg hook: header does not match Conventional Commits format" >&2
    echo "" >&2
    echo "  Got:      $header" >&2
    echo "  Expected: <type>(<scope>): <description>" >&2
    echo "" >&2
    echo "  types: build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test" >&2
    echo "  example: feat(chat): add dictation stream view" >&2
    exit 1
fi

exit 0
