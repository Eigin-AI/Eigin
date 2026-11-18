"""Select independent Linux checks; uncertain comparisons always run all checks."""

import json
import os
import sys

from mr_diff import changed_paths

COMPONENTS = {"relay", "postgres", "sdk"}


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
