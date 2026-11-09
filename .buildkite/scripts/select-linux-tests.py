"""Select independent Linux checks; uncertain comparisons always run all checks."""

import json
import os
import subprocess
import sys

COMPONENTS = {"relay", "postgres", "sdk"}


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
        target = context.get("LINUX_DIFF_TARGET", "")
        commit = context.get("BUILDKITE_COMMIT", "")
        if not all(len(sha) == 40 and all(c in "0123456789abcdef" for c in sha)
                   for sha in (target, commit)):
            raise ValueError("missing or invalid comparison commit")
        base = git("merge-base", target, commit).decode().strip()
        paths = git("diff", "--no-renames", "--name-only", "-z", base, commit, "--")
        print(f"Linux comparison: {base}..{commit}", file=sys.stderr)
        return {os.fsdecode(path) for path in paths.split(b"\0") if path}
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Linux comparison unavailable: {error}; running all checks", file=sys.stderr)
        return None


def select_components(paths):
    """Map component and shared build inputs to affected checks."""
    if paths is None:
        return set(COMPONENTS)
    selected = set()
    for path in paths:
        if (path.startswith((".buildkite/", "tools/", ".cargo/"))
                or path in {"justfile", "Cargo.toml", "Cargo.lock", "rust-toolchain", "rust-toolchain.toml"}):
            return set(COMPONENTS)
        if path.startswith("src/eigin_relay/"):
            selected.update({"relay", "postgres"})
        if path.startswith("src/eigin_sdk/"):
            selected.add("sdk")
    return selected


def make_pipeline(components):
    """Generate credential-free jobs with separate caches and concurrency limits."""
    labels = {"relay": "Relay tests", "postgres": "Relay Postgres integration", "sdk": "Rust SDK checks"}
    return {"steps": [
        {
            "label": f":rust: {labels[component]}",
            "key": f"linux-{component}",
            "agents": {"queue": "linux-small"},
            "timeout_in_minutes": 30,
            "concurrency": 2,
            "concurrency_group": f"eigin/linux-{component}",
            "cache": {
                "name": f"linux-{component}-rust-1-99-1-v1",
                "size": "20g",
                "paths": [f"/cache/eigin-linux-{component}"],
            },
            "command": f"bash .buildkite/scripts/run-linux-tests.sh {component}",
        }
        for component in sorted(components)
    ]}


def main():
    """Emit only pipeline JSON on stdout; upload errors remain build failures."""
    selected = select_components(changed_paths(os.environ))
    print(f"Linux checks selected: {', '.join(sorted(selected)) or 'none'}", file=sys.stderr)
    # Buildkite rejects an empty upload; a no-op records intentional selection.
    pipeline = make_pipeline(selected)
    if not selected:
        pipeline = {"steps": [{"label": "Linux checks: no affected components", "command": "true",
                               "agents": {"queue": "linux-small"}, "timeout_in_minutes": 1}]}
    json.dump(pipeline, sys.stdout)
    print()


if __name__ == "__main__":
    main()
