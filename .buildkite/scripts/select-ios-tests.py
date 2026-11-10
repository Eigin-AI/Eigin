#!/usr/bin/env python3
"""Emit the approved macOS job with main/MR cache isolation."""

import json
import os


def pipeline(branch):
    """Return one certificate-free simulator job without secrets."""
    scope = "main" if branch == "main" else "mr"
    return {"steps": [{
        "label": ":apple: iOS simulator tests", "key": "ios-tests",
        "agents": {"queue": "macos-medium"},
        "timeout_in_minutes": 60, "concurrency": 1,
        "concurrency_group": "eigin/ios-tests",
        "cache": {"name": f"ios-{scope}-xcode-17c52-rust-1-99-1-v2", "size": "30g",
                  "paths": ["~/.cache/eigin-ios"]},
        "artifact_paths": ["logs/ios-ci/**/*"],
        "command": "python3 .buildkite/scripts/test-ios.py",
    }]}


if __name__ == "__main__":
    print(json.dumps(pipeline(os.environ.get("BUILDKITE_BRANCH", ""))))
