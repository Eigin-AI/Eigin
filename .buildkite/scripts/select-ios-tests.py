#!/usr/bin/env python3
"""Require manual iOS tests for relevant MRs; uncertain diffs require tests."""

import json
import os

from mr_diff import changed_paths


def requires_tests(paths):
    """Include app sources and shared generation, configuration, and build inputs."""
    if paths is None:
        return True
    return any(path.startswith(("src/eigin_ios/", "src/eigin_sdk/", "design/", "config/",
                                "tools/", ".cargo/", ".buildkite/"))
               or path in {"justfile", "Cargo.toml", "Cargo.lock", "rust-toolchain",
                           "rust-toolchain.toml", ".env.example"}
               for path in paths)


def pipeline(branch, paths=None):
    """Return one certificate-free simulator job without secrets."""
    scope = "main" if branch == "main" else "mr"
    if branch != "main" and not requires_tests(paths):
        return {"steps": [{
            "label": "iOS tests not required: no affected inputs", "key": "ios-not-required",
            "agents": {"queue": "linux-small"}, "timeout_in_minutes": 1,
            "command": "echo 'Full MR diff has no iOS or shared build input changes.'",
        }]}
    steps = [{
        "label": ":apple: iOS simulator tests", "key": "ios-tests",
        "agents": {"queue": "macos-medium"},
        "timeout_in_minutes": 60, "concurrency": 1,
        "concurrency_group": "eigin/ios-tests",
        "cache": {"name": f"ios-{scope}-xcode-17c52-rust-1-99-1-v2", "size": "30g",
                  "paths": ["~/.cache/eigin-ios"]},
        "artifact_paths": ["logs/ios-ci/**/*"],
        "command": "python3 .buildkite/scripts/test-ios.py",
    }]
    if branch != "main":
        steps[0]["depends_on"] = "ios-test-approval"
        steps.insert(0, {
            "block": "Run iOS tests", "key": "ios-test-approval",
            "blocked_state": "running",
            "prompt": "Run required simulator tests for this MR commit? A new commit requires a new run.",
            "depends_on": "ios-select",
        })
    return {"steps": steps}


if __name__ == "__main__":
    branch = os.environ.get("BUILDKITE_BRANCH", "")
    paths = None if branch == "main" else changed_paths(os.environ)
    print(json.dumps(pipeline(branch, paths)))
