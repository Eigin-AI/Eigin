"""Exercise docs script boundaries without credentials or network access."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import sys
import contextlib
import importlib.util
from unittest.mock import patch
import unittest

ROOT = Path(__file__).resolve().parents[2]


class FontsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        script = self.root / ".buildkite/scripts/download-docs-fonts.py"
        script.parent.mkdir(parents=True)
        shutil.copy(ROOT / ".buildkite/scripts/download-docs-fonts.py", script)
        self.script = script
        (self.root / "docs").mkdir()
        (self.root / "docs/fonts.json").write_text(json.dumps({
            "test.otf": hashlib.sha256(b"font").hexdigest()
        }))
        self.bin = self.root / "bin"
        self.bin.mkdir()
        curl = self.bin / "curl"
        curl.write_text('''#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
assert args[args.index('--header') + 1] == os.environ['EXPECTED_AUTH']
mode = os.environ.get('MODE', 'ok')
if mode == 'http':
    sys.exit(22)
if args[-1].endswith('per_page=100'):
    files = [{'name': 'test.otf', 'id': 1}]
    if mode == 'missing': files = []
    if mode == 'duplicate': files *= 2
    print(json.dumps(files))
else:
    sys.stdout.write('bad' if mode == 'checksum' else 'font')
''')
        curl.chmod(0o755)
        self.env = {
            **os.environ,
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "CI_API_V4_URL": "https://gitlab.invalid/api/v4",
            "CI_PROJECT_ID": "2",
            "DOCS_GITLAB_TOKEN": "test-token",
            "EXPECTED_AUTH": "PRIVATE-TOKEN: test-token",
        }
        self.env.pop("CI_JOB_TOKEN", None)

    def run_download(self, mode="ok"):
        return subprocess.run(
            [sys.executable, str(self.script)], cwd=self.root, env={**self.env, "MODE": mode},
            capture_output=True, text=True,
        )

    def test_project_token(self):
        result = self.run_download()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "design/assets/fonts/docs/test.otf").read_bytes(), b"font")

    def test_job_token_compatibility(self):
        self.env.pop("DOCS_GITLAB_TOKEN")
        self.env.update(CI_JOB_TOKEN="job-token", EXPECTED_AUTH="JOB-TOKEN: job-token")
        result = self.run_download()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_credentials(self):
        self.env.pop("DOCS_GITLAB_TOKEN")
        self.assertNotEqual(self.run_download().returncode, 0)

    def test_download_errors(self):
        for mode in ("missing", "duplicate", "http", "checksum"):
            with self.subTest(mode=mode):
                result = self.run_download(mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.root / "design/assets/fonts/docs/test.otf").exists())


class PublishTest(unittest.TestCase):
    def test_rejects_untrusted_build_context_before_network(self):
        for branch, pr, source in (
            ("feature/86-cicd", "309", "webhook"),
            ("main", "309", "webhook"),
            ("main", "false", "ui"),
        ):
            with self.subTest(branch=branch, pr=pr, source=source):
                env = {
                    **os.environ, "BUILDKITE_BRANCH": branch,
                    "BUILDKITE_PULL_REQUEST": pr, "BUILDKITE_SOURCE": source,
                    "BUILDKITE_COMMIT": "test", "AWS_ACCESS_KEY_ID": "test",
                    "AWS_SECRET_ACCESS_KEY": "test",
                }
                result = subprocess.run(
                    [sys.executable, str(ROOT / ".buildkite/scripts/publish-docs.py")],
                    env=env, capture_output=True, text=True,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("requires a main webhook build", result.stderr)


    def test_stale_build_skips_upload(self):
        spec = importlib.util.spec_from_file_location("publish", ROOT / ".buildkite/scripts/publish-docs.py")
        sys.path.insert(0, str(ROOT / ".buildkite/scripts"))
        publish = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(publish)
        env = {"BUILDKITE_BRANCH": "main", "BUILDKITE_PULL_REQUEST": "false",
               "BUILDKITE_SOURCE": "webhook", "BUILDKITE_COMMIT": "old",
               "AWS_ACCESS_KEY_ID": "test", "AWS_SECRET_ACCESS_KEY": "test"}
        with patch.dict(os.environ, env), patch.object(publish, "run") as run, \
                patch.object(publish, "download") as download:
            run.return_value.stdout = "new\trefs/heads/main\n"
            publish.main()
            self.assertEqual(run.call_count, 1)
            download.assert_not_called()

    def test_current_build_requires_nonempty_index(self):
        spec = importlib.util.spec_from_file_location("publish", ROOT / ".buildkite/scripts/publish-docs.py")
        sys.path.insert(0, str(ROOT / ".buildkite/scripts"))
        publish = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(publish)
        env = {"BUILDKITE_BRANCH": "main", "BUILDKITE_PULL_REQUEST": "false",
               "BUILDKITE_SOURCE": "webhook", "BUILDKITE_COMMIT": "current",
               "AWS_ACCESS_KEY_ID": "test", "AWS_SECRET_ACCESS_KEY": "test"}
        with tempfile.TemporaryDirectory() as directory, contextlib.chdir(directory), \
                patch.dict(os.environ, env), patch.object(publish, "run") as run, \
                patch.object(publish, "download") as download:
            run.return_value.stdout = "current\trefs/heads/main\n"
            with self.assertRaisesRegex(SystemExit, "missing or empty"):
                publish.main()
            download.assert_not_called()


if __name__ == "__main__":
    unittest.main()
