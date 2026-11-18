"""Exercise MR selection and required approval with real comparison history."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from test_ios import selector
import test_linux_upload
from test_pipeline_flow import ready

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/select-ios-tests.py"


class SelectionTests(unittest.TestCase):
    def test_shared_inputs_require_tests(self):
        for path in ("src/eigin_ios/App.swift", "src/eigin_sdk/Cargo.lock", "design/prompts/a",
                     "design/tokens.json", "config/default.toml", "tools/src/main.rs",
                     ".buildkite/pipeline.yml", ".cargo/config.toml", "justfile", ".env.example",
                     "Cargo.lock", "rust-toolchain.toml"):
            with self.subTest(path=path):
                self.assertTrue(selector.requires_tests({path}))

    def test_unrelated_changes_do_not_allocate_mac_or_require_approval(self):
        for paths in (set(), {"docs/a.md", "src/eigin_relay/a.rs", "README.md"}):
            steps = selector.pipeline("feature/test", paths)["steps"]
            self.assertEqual(len(steps), 1)
            self.assertEqual(steps[0]["key"], "ios-not-required")
            self.assertEqual(steps[0]["agents"]["queue"], "linux-small")
            self.assertNotIn("block", steps[0])

    def test_relevant_or_unknown_diff_requires_approval_before_mac(self):
        for paths in (None, {"src/eigin_ios/a.swift"}):
            steps = {s["key"]: s for s in selector.pipeline("feature/test", paths)["steps"]}
            steps["ios-select"] = {"depends_on": []}
            self.assertEqual(ready(steps, set()), {"ios-select"})
            self.assertEqual(ready(steps, {"ios-select"}), {"ios-test-approval"})
            self.assertEqual(steps["ios-test-approval"]["blocked_state"], "running")
            self.assertNotIn("agents", steps["ios-test-approval"])
            self.assertEqual(ready(steps, {"ios-select", "ios-test-approval"}), {"ios-tests"})
            self.assertNotIn("soft_fail", steps["ios-tests"])
            self.assertNotIn("allow_dependency_failure", steps["ios-tests"])

    def test_main_keeps_existing_policy(self):
        steps = selector.pipeline("main", set())["steps"]
        self.assertEqual(len(steps), 1)
        self.assertEqual(steps[0]["key"], "ios-tests")
        self.assertNotIn("depends_on", steps[0])

    def run_selector(self, directory, **context):
        result = subprocess.run([sys.executable, str(SCRIPT)], cwd=directory,
                                env={**os.environ, "BUILDKITE_BRANCH": "feature/test",
                                     "BUILDKITE_PULL_REQUEST": "12", "MR_DIFF_TARGET": "",
                                     "BUILDKITE_COMMIT": "", **context},
                                capture_output=True, text=True, check=True)
        return json.loads(result.stdout), result.stderr

    def test_missing_invalid_or_unavailable_comparison_requires_tests(self):
        with tempfile.TemporaryDirectory() as directory:
            for context in ({}, {"MR_DIFF_TARGET": "--bad"},
                            {"MR_DIFF_TARGET": "a" * 40, "BUILDKITE_COMMIT": "b" * 40}):
                pipeline, log = self.run_selector(directory, **context)
                self.assertEqual(pipeline["steps"][0]["key"], "ios-test-approval")
                self.assertIn("comparison unavailable", log)

    def test_full_mr_diff_keeps_earlier_ios_deletion_after_docs_push(self):
        with tempfile.TemporaryDirectory() as directory:
            def git(*args):
                return subprocess.check_output(["git", "-C", directory, *args],
                                               stderr=subprocess.DEVNULL).decode().strip()

            git("init")
            git("config", "user.email", "ci@example.test")
            git("config", "user.name", "CI")
            root = Path(directory)
            source = root / "src/eigin_ios/space\nname.swift"
            source.parent.mkdir(parents=True)
            source.write_text("source")
            git("add", ".")
            git("commit", "-m", "base")
            base = git("rev-parse", "HEAD")
            source.unlink()
            git("add", ".")
            git("commit", "-m", "delete iOS source")
            (root / "README.md").write_text("docs")
            git("add", ".")
            git("commit", "-m", "docs follow-up")
            pipeline, _ = self.run_selector(directory, MR_DIFF_TARGET=base,
                                            BUILDKITE_COMMIT=git("rev-parse", "HEAD"))
            self.assertEqual(pipeline["steps"][0]["key"], "ios-test-approval")
            pipeline, _ = self.run_selector(directory, MR_DIFF_TARGET=base, BUILDKITE_COMMIT=base)
            self.assertEqual(pipeline["steps"][0]["key"], "ios-not-required")


class IOSUploadTests(test_linux_upload.UploadTests):
    script = ".buildkite/scripts/upload-ios-tests.sh"
    target_variable = "MR_DIFF_TARGET"


if __name__ == "__main__":
    unittest.main()
