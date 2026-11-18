"""Compare complete merge requests; unavailable baselines require tests."""

import os
import subprocess
import sys


def git(*args):
    """Capture Git output without interpreting paths or shell syntax."""
    # The read-only checkout belongs to the runner user, not container root.
    return subprocess.check_output(["git", "-c", "safe.directory=/work", *args], stderr=subprocess.PIPE)


def changed_paths(context):
    """Return the full MR diff, or None when no trustworthy baseline exists."""
    try:
        if context.get("BUILDKITE_PULL_REQUEST", "false") in ("", "false"):
            # Buildkite does not supply a verified pre-push SHA by default.
            raise ValueError("no verified pre-push baseline")
        target = context.get("MR_DIFF_TARGET", "")
        commit = context.get("BUILDKITE_COMMIT", "")
        if not all(len(sha) == 40 and all(c in "0123456789abcdef" for c in sha)
                   for sha in (target, commit)):
            raise ValueError("missing or invalid comparison commit")
        base = git("merge-base", target, commit).decode().strip()
        paths = git("diff", "--no-renames", "--name-only", "-z", base, commit, "--")
        print(f"MR comparison: {base}..{commit}", file=sys.stderr)
        return {os.fsdecode(path) for path in paths.split(b"\0") if path}
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"MR comparison unavailable: {error}; tests required", file=sys.stderr)
        return None
