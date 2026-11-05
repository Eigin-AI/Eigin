"""Exercise version orchestration and verified downloads at external boundaries."""

import contextlib
import hashlib
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))
import ci_tools

SPEC = importlib.util.spec_from_file_location("versions", SCRIPTS / "check-versions.py")
versions = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(versions)


class VersionsTests(unittest.TestCase):
    def test_checks_run_in_order_with_timings(self):
        output = io.StringIO()
        with patch.object(versions, "install_node"), patch.object(versions, "install_just"), \
                patch.object(versions, "run") as run, contextlib.redirect_stdout(output):
            versions.main()
        self.assertIn("check", run.call_args_list[0].args)
        self.assertEqual([c.args[-1] for c in run.call_args_list[1:]], ["version", "releases"])
        self.assertEqual(output.getvalue().count("Duration:"), 5)

    def test_failed_command_stops_tests(self):
        with patch.object(versions, "install_node"), patch.object(versions, "install_just"), \
                patch.object(versions, "run", side_effect=subprocess.CalledProcessError(7, "cargo")) as run, \
                contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(subprocess.CalledProcessError):
                versions.main()
        self.assertEqual(run.call_count, 1)

    def test_download_failure_prevents_extraction_and_checks(self):
        with tempfile.TemporaryDirectory() as directory, \
                patch.dict(os.environ, {"CARGO_HOME": directory}), \
                patch.object(ci_tools, "run", side_effect=subprocess.CalledProcessError(7, "curl")), \
                patch.object(versions, "extract") as extract, \
                patch.object(versions, "run") as run, contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(subprocess.CalledProcessError):
                versions.main()
            extract.assert_not_called()
            run.assert_not_called()

    def test_cached_node_is_verified_before_extraction(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"CARGO_HOME": directory}):
            archive = Path(directory) / "downloads" / f"node-v{versions.NODE}-linux-x64.tar.xz"
            archive.parent.mkdir()
            archive.write_bytes(b"wrong archive")
            with patch.object(versions, "extract") as extract, patch.object(ci_tools, "run") as run:
                with self.assertRaisesRegex(ValueError, "checksum"):
                    versions.install_node(directory)
                extract.assert_not_called()
                run.assert_not_called()
                self.assertFalse(archive.exists())

    def test_download_cache_hit_and_miss_verify_actual_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "archive"
            def fetch(*args):
                Path(args[-1]).write_bytes(b"archive")
            with patch.object(ci_tools, "run", side_effect=fetch) as run:
                digest = hashlib.sha256(b"archive").hexdigest()
                ci_tools.download("https://example.invalid/archive", path, digest)
                ci_tools.download("https://example.invalid/archive", path, digest)
                self.assertEqual(run.call_count, 1)
                self.assertEqual(path.read_bytes(), b"archive")

    def test_archive_traversal_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "archive.tar"
            with tarfile.open(archive, "w") as tar:
                entry = tarfile.TarInfo("../escape")
                entry.size = 1
                tar.addfile(entry, io.BytesIO(b"x"))
            with self.assertRaises(ValueError):
                ci_tools.extract(archive, Path(directory) / "out")


    def test_internal_symlink_and_executable_are_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "archive.tar"
            with tarfile.open(archive, "w") as tar:
                entry = tarfile.TarInfo("node/bin/node")
                entry.size = 1
                entry.mode = 0o4755
                tar.addfile(entry, io.BytesIO(b"x"))
                link = tarfile.TarInfo("node/bin/npm")
                link.type = tarfile.SYMTYPE
                link.linkname = "node"
                tar.addfile(link)
            destination = Path(directory) / "out"
            ci_tools.extract(archive, destination)
            self.assertEqual((destination / "node/bin/npm").read_bytes(), b"x")
            self.assertEqual((destination / "node/bin/node").stat().st_mode & 0o7777, 0o755)

    def test_unsafe_entries_rejected(self):
        for name, kind, target in (("/absolute", tarfile.REGTYPE, ""),
                                   ("link", tarfile.SYMTYPE, "../escape"),
                                   ("link", tarfile.SYMTYPE, "/absolute"),
                                   ("device", tarfile.CHRTYPE, ""),
                                   ("hardlink", tarfile.LNKTYPE, "../escape")):
            with self.subTest(name=name, target=target), tempfile.TemporaryDirectory() as directory:
                archive = Path(directory) / "archive.tar"
                with tarfile.open(archive, "w") as tar:
                    entry = tarfile.TarInfo(name)
                    entry.type = kind
                    entry.linkname = target
                    tar.addfile(entry)
                with self.assertRaises(ValueError):
                    ci_tools.extract(archive, Path(directory) / "out")


if __name__ == "__main__":
    unittest.main()
