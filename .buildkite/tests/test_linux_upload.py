"""Exercise the host upload entry point with fake external commands."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class UploadTests(unittest.TestCase):
    def upload(self, failure="", branch="main", pull_request="12"):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            command = '''#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["COMMAND_LOG"], "a") as log:
    log.write(json.dumps([name, args, os.environ.get("LINUX_DIFF_TARGET")]) + "\\n")
if name == os.environ.get("FAIL_COMMAND"):
    sys.exit(7)
if name == "git" and args[0] == "rev-parse":
    print("a" * 40)
if name == "docker":
    print('{"steps": [{"command": "true"}]}')
if name == "buildkite-agent":
    json.loads(pathlib.Path(args[2]).read_text())
'''
            for name in ("git", "docker", "buildkite-agent"):
                path = root / name
                path.write_text(command)
                path.chmod(0o755)
            env = {**os.environ, "PATH": f"{root}:{os.environ['PATH']}",
                   "COMMAND_LOG": str(root / "log"), "FAIL_COMMAND": failure,
                   "BUILDKITE_PULL_REQUEST": pull_request,
                   "BUILDKITE_PULL_REQUEST_BASE_BRANCH": branch}
            result = subprocess.run(["bash", ".buildkite/scripts/upload-linux-tests.sh"],
                                    cwd=ROOT, env=env, capture_output=True)
            calls = [json.loads(line) for line in (root / "log").read_text().splitlines()]
            return result, calls

    def test_fetched_sha_reaches_selector_and_pipeline_upload(self):
        result, calls = self.upload()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(["git", ["fetch", "--no-tags", "origin", "refs/heads/main"], ""], calls)
        docker = next(call for call in calls if call[0] == "docker")
        self.assertEqual(docker[2], "a" * 40)
        self.assertEqual(calls[-1][0], "buildkite-agent")

    def test_selector_failure_prevents_upload(self):
        result, calls = self.upload(failure="docker")
        self.assertEqual(result.returncode, 7)
        self.assertFalse(any(call[0] == "buildkite-agent" for call in calls))

    def test_upload_failure_fails_job(self):
        result, _ = self.upload(failure="buildkite-agent")
        self.assertEqual(result.returncode, 7)

    def test_fetch_failure_selects_all_instead_of_skipping(self):
        result, calls = self.upload(failure="git")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(next(call[2] for call in calls if call[0] == "docker"), "")

    def test_main_never_assumes_previous_commit_is_push_base(self):
        result, calls = self.upload(pull_request="false")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(call[0] == "git" for call in calls))
        self.assertEqual(next(call[2] for call in calls if call[0] == "docker"), "")
