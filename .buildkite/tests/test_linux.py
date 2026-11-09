"""Exercise selection with real Git history and orchestration at process boundaries."""

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


selection = load("selection", "select-linux-tests.py")
checks = load("checks", "check-linux.py")


class SelectionTests(unittest.TestCase):
    def test_path_selection(self):
        cases = [
            (None, selection.COMPONENTS),
            (set(), set()),
            ({"docs/a.md", "design/tokens.json", "package-lock.json"}, set()),
            ({"src/eigin_relay/migrations/1.sql"}, {"relay", "postgres"}),
            ({"src/eigin_relay/vendor/sqlx-core/src/pool.rs"}, {"relay", "postgres"}),
            ({"src/eigin_sdk/Cargo.lock"}, {"sdk"}),
            ({"tools/src/generate.rs"}, selection.COMPONENTS),
            ({".buildkite/scripts/check-linux.py"}, selection.COMPONENTS),
            ({"justfile"}, selection.COMPONENTS),
            ({".cargo/config.toml"}, selection.COMPONENTS),
            ({"src/eigin_sdk/a", "src/eigin_relay/b"}, selection.COMPONENTS),
        ]
        for paths, expected in cases:
            with self.subTest(paths=paths):
                self.assertEqual(selection.select_components(paths), expected)

    def test_pipeline_limits_and_isolation(self):
        pipeline = selection.make_pipeline(selection.COMPONENTS)
        json.dumps(pipeline)
        self.assertEqual(len(pipeline["steps"]), 3)
        for step in pipeline["steps"]:
            self.assertEqual(step["concurrency"], 2)
            self.assertEqual(step["timeout_in_minutes"], 30)
            self.assertNotIn("secrets", step)
            self.assertNotIn("depends_on", step)
            self.assertNotIn("soft_fail", step)
        self.assertEqual(len({s["cache"]["name"] for s in pipeline["steps"]}), 3)

    def test_main_and_invalid_or_missing_history_run_all(self):
        for context in [{}, {"BUILDKITE_PULL_REQUEST": "false"},
                        {"BUILDKITE_PULL_REQUEST": "1", "LINUX_DIFF_TARGET": "--bad"},
                        {"BUILDKITE_PULL_REQUEST": "1", "LINUX_DIFF_TARGET": "a" * 40,
                         "BUILDKITE_COMMIT": "b" * 40}]:
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertIsNone(selection.changed_paths(context))

    def test_full_mr_diff_includes_earlier_commits_deletions_and_renames(self):
        with tempfile.TemporaryDirectory() as directory:
            def git(*args):
                return subprocess.check_output(["git", "-C", directory, *args], stderr=subprocess.DEVNULL).decode().strip()

            git("init")
            git("config", "user.email", "ci@example.test")
            git("config", "user.name", "CI")
            root = Path(directory)
            (root / "old").write_text("old")
            git("add", ".")
            git("commit", "-m", "base")
            base = git("rev-parse", "HEAD")
            (root / "src/eigin_relay").mkdir(parents=True)
            (root / "src/eigin_relay/space\nname.rs").write_text("test")
            git("add", ".")
            git("commit", "-m", "relay")
            git("mv", "old", "renamed")
            git("commit", "-m", "rename")
            commit = git("rev-parse", "HEAD")
            with patch.object(selection, "git", side_effect=lambda *args: subprocess.check_output(
                    ["git", "-C", directory, *args])), contextlib.redirect_stderr(io.StringIO()):
                paths = selection.changed_paths({"BUILDKITE_PULL_REQUEST": "1",
                                                 "LINUX_DIFF_TARGET": base, "BUILDKITE_COMMIT": commit})
            self.assertEqual(paths, {"old", "renamed", "src/eigin_relay/space\nname.rs"})
            self.assertEqual(selection.select_components(paths), {"relay", "postgres"})

    def test_no_changes_emits_valid_noop_pipeline(self):
        with patch.object(selection, "changed_paths", return_value=set()), \
                contextlib.redirect_stdout(io.StringIO()) as output, \
                contextlib.redirect_stderr(io.StringIO()):
            selection.main()
        self.assertEqual(json.loads(output.getvalue())["steps"][0]["command"], "true")


class CheckTests(unittest.TestCase):
    def test_sdk_contract_and_fail_fast(self):
        commands = checks.commands("sdk")
        self.assertIn("wasm32-unknown-unknown", commands[3])
        self.assertIn("binding-tests", commands[4])
        self.assertIn("clippy", commands[5])
        self.assertEqual(commands[6][-1], "--check")
        with patch.object(checks, "run", side_effect=subprocess.CalledProcessError(3, "cargo")) as run, \
                contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(subprocess.CalledProcessError):
                checks.main("sdk")
            self.assertEqual(run.call_count, 1)

    def test_relay_tests_use_locked_dependencies(self):
        self.assertIn("--locked", checks.commands("relay")[0])
        self.assertEqual(checks.commands("postgres")[0][-3:], ["--", "--ignored", "--nocapture"])


class DockerOrchestrationTests(unittest.TestCase):
    def run_job(self, component, fail_tests=False, never_ready=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            docker = root / "docker"
            docker.write_text('''#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
with open(os.environ["DOCKER_LOG"], "a") as log:
    log.write(json.dumps(args) + "\\n")
if args[0] == "exec" and os.environ.get("NEVER_READY") == "1":
    sys.exit(1)
if args[0] == "run" and "python3" in args and os.environ.get("FAIL_TESTS") == "1":
    sys.exit(7)
''')
            docker.chmod(0o755)
            # Avoid readiness delay in boundary tests; production uses real sleep.
            sleep = root / "sleep"
            sleep.write_text("#!/bin/sh\nexit 0\n")
            sleep.chmod(0o755)
            timeout = root / "timeout"
            timeout.write_text('#!/bin/sh\nshift 2\nexec "$@"\n')
            timeout.chmod(0o755)
            # Substitute the Linux UUID source for portable shell boundary tests.
            script = (SCRIPTS / "run-linux-tests.sh").read_text().replace(
                "$(cat /proc/sys/kernel/random/uuid)", "test-unique-id").replace(
                "$(uuidgen)", "test-unique-id")
            env = {**os.environ, "PATH": f"{directory}:{os.environ['PATH']}",
                   "DOCKER_LOG": str(root / "log"), "FAIL_TESTS": str(int(fail_tests)),
                   "NEVER_READY": str(int(never_ready))}
            result = subprocess.run(["bash", "-c", script, "--", component],
                                    cwd=SCRIPTS.parents[1], env=env, capture_output=True)
            calls = [json.loads(line) for line in (root / "log").read_text().splitlines()]
            return result, calls

    def test_relay_does_not_require_database_or_network_options(self):
        result, calls = self.run_job("relay")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sum(c[0] == "run" for c in calls), 1)
        self.assertFalse(any(c[0] == "exec" for c in calls))

    def test_postgres_is_local_isolated_and_cleaned(self):
        result, calls = self.run_job("postgres")
        self.assertEqual(result.returncode, 0, result.stderr)
        runs = [c for c in calls if c[0] == "run"]
        self.assertEqual(len(runs), 2)
        self.assertNotIn("-p", runs[0])
        readiness = next(c for c in calls if c[0] == "exec")
        self.assertIn("127.0.0.1", readiness)
        self.assertIn("container:eigin-postgres-test-unique-id", runs[1])
        self.assertIn("DATABASE_URL=postgres://postgres:postgres@localhost/postgres", runs[1])
        self.assertIn("POOL_TEST_DATABASE_URL=postgres://postgres:postgres@localhost/postgres", runs[1])
        self.assertNotIn("/var/run/docker.sock", " ".join(runs[1]))
        self.assertTrue(any(c[:3] == ["rm", "--force", "--volumes"] for c in calls))

    def test_failure_preserves_exit_status_and_cleans_both_containers(self):
        result, calls = self.run_job("postgres", fail_tests=True)
        self.assertEqual(result.returncode, 7)
        self.assertEqual(sum(c[0] == "rm" for c in calls), 2)
        self.assertTrue(any(c[0] == "logs" for c in calls))

    def test_readiness_is_bounded_and_prevents_test_execution(self):
        result, calls = self.run_job("postgres", never_ready=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(sum(c[0] == "exec" for c in calls), 60)
        self.assertEqual(sum(c[0] == "run" for c in calls), 1)
        self.assertTrue(any(c[:3] == ["rm", "--force", "--volumes"] for c in calls))


if __name__ == "__main__":
    unittest.main()
