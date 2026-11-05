"""CLA behavior tested at the GitLab HTTP boundary."""

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import unittest
from unittest.mock import patch
import urllib.error

SPEC = importlib.util.spec_from_file_location(
    "cla", Path(__file__).parents[1] / "scripts/check-cla.py"
)
cla = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(cla)


class ClaTests(unittest.TestCase):
    def setUp(self):
        self.env = {
            "BUILDKITE_PULL_REQUEST": "309", "BUILDKITE_COMMIT": "a" * 40,
            "CLA_READ_TOKEN": "read-secret", "CLA_BOT_TOKEN": "bot-secret",
        }
        self.mr = {
            "iid": 309, "source_project_id": 2, "target_project_id": 2,
            "sha": "a" * 40, "state": "opened",
            "author": {"id": 42, "username": "contributor"},
        }
        self.csv = "id,username,version\n42,contributor,1.0\n"
        self.pages = {1: ([], {})}
        self.calls = []
        self.failure = None

    def api(self, path, token, body=None):
        self.calls.append((path, token, body))
        if self.failure and self.failure in path:
            raise cla.CheckError("GitLab request failed.")
        if path == cla.SIGNATURES:
            self.assertEqual(token, "read-secret")
            return self.csv, {}
        self.assertEqual(token, "bot-secret")
        if "notes?" in path:
            notes, headers = self.pages[int(path.rsplit("=", 1)[1])]
            return json.dumps(notes), headers
        if body is not None:
            return "{}", {}
        return json.dumps(self.mr), {}

    def run_check(self):
        with contextlib.redirect_stdout(io.StringIO()):
            return cla.check(self.env, self.api)

    def unsigned(self):
        self.csv = "id,username,version\n99,someone,1.0\n"

    def test_signed_author_passes_without_notes(self):
        self.assertEqual(self.run_check(), 0)
        self.assertEqual(len(self.calls), 2)

    def test_unsigned_posts_and_fails(self):
        self.unsigned()
        self.assertEqual(self.run_check(), 1)
        self.assertEqual(self.calls[-1][2], {"body": cla.instructions("contributor")})
        self.assertIn(cla.PHRASE, self.calls[-1][2]["body"])

    def test_existing_paginated_note_prevents_post(self):
        self.unsigned()
        self.pages = {1: ([], {"X-Next-Page": "2"}), 2: ([{"body": cla.MARKER}], {})}
        self.assertEqual(self.run_check(), 1)
        self.assertTrue(all(body is None for _, _, body in self.calls))

    def test_api_failures_fail_closed(self):
        for endpoint in ("merge_requests", "signatures.csv", "/notes"):
            with self.subTest(endpoint=endpoint):
                self.unsigned()
                self.failure = endpoint
                with self.assertRaises(cla.CheckError):
                    self.run_check()

    def test_post_failure_fails_closed(self):
        self.unsigned()
        def api(path, token, body=None):
            if body is not None:
                raise cla.CheckError("GitLab request failed.")
            return self.api(path, token, body)
        with self.assertRaises(cla.CheckError), contextlib.redirect_stdout(io.StringIO()):
            cla.check(self.env, api)

    def test_mr_identity_and_head_must_match(self):
        for key, value in (("iid", 1), ("source_project_id", 3),
                           ("target_project_id", 3), ("sha", "b" * 40),
                           ("state", "closed"), ("author", None)):
            with self.subTest(key=key), patch.dict(self.mr, {key: value}):
                with self.assertRaises(cla.CheckError):
                    self.run_check()

    def test_injection_metadata_rejected_before_api(self):
        for key in ("BUILDKITE_PULL_REQUEST", "BUILDKITE_COMMIT"):
            with self.subTest(key=key), patch.dict(self.env, {key: "$(touch /tmp/cla)"}):
                with self.assertRaises(cla.CheckError):
                    self.run_check()
        self.assertEqual(self.calls, [])

    def test_missing_credentials_rejected(self):
        del self.env["CLA_READ_TOKEN"]
        with self.assertRaises(cla.CheckError):
            self.run_check()
        self.assertEqual(self.calls, [])

    def test_invalid_author_and_csv_rejected(self):
        self.mr["author"]["username"] = "$(command)"
        with self.assertRaises(cla.CheckError):
            self.run_check()
        self.mr["author"]["username"] = "contributor"
        for text in ("", "not,csv\nsecret\n", 'id,name\n42,"unterminated'):
            self.csv = text
            with self.subTest(text=text), self.assertRaises(cla.CheckError):
                self.run_check()

    def test_malformed_notes_and_pagination_rejected(self):
        self.unsigned()
        for page in (({}, {}), ([{"body": None}], {}), ([], {"X-Next-Page": "1"}),
                     ([], {"X-Next-Page": "https://attacker.invalid"})):
            self.pages = {1: page}
            with self.subTest(page=page), self.assertRaises(cla.CheckError):
                self.run_check()

    def test_redirects_are_not_followed(self):
        self.assertIsNone(cla.NoRedirect().redirect_request(
            None, None, 302, "Found", {}, "https://attacker.invalid"
        ))

    def test_http_errors_do_not_disclose_bodies_or_tokens(self):
        with patch.object(cla.urllib.request, "build_opener") as opener:
            opener.return_value.open.side_effect = urllib.error.HTTPError(
                cla.API, 403, "private secret", {}, io.BytesIO(b"signature data")
            )
            with self.assertRaisesRegex(cla.CheckError, r"^GitLab request failed\.$"):
                cla.request("projects/2", "private-token")

    def test_invalid_json_is_sanitized(self):
        with self.assertRaisesRegex(cla.CheckError, r"^Invalid GitLab response\.$"):
            cla.decode("private response")


if __name__ == "__main__":
    unittest.main()
