#!/usr/bin/env bash
set -euo pipefail

# log-wrapper.sh
# Runs a command, captures all output to a log file, and prints a concise result.
#
# Usage: log-wrapper.sh <log-file> <label> <command...>

log_file="$1"
label="$2"
shift 2

mkdir -p "$(dirname "$log_file")"

echo "→ $label..."

if "$@" > "$log_file" 2>&1; then
    echo "✓ $label succeeded. Full log: $log_file"
else
    exit_code=$?
    echo "✗ $label failed. Full log: $log_file"
    echo ""
    echo "--- Last 30 lines ---"
    tail -n 30 "$log_file"
    echo "--- End of tail ---"
    exit $exit_code
fi
