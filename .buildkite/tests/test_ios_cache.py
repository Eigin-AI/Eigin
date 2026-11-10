"""Exercise cached workspace reuse with real rsync, Git and Cargo processes."""

import os
from pathlib import Path
import subprocess
import shutil
import tempfile
import sys
import unittest

sys.path.insert(0, str(Path(__file__).parents[1] / "scripts"))
from ios_workspace import prepare


@unittest.skipUnless(shutil.which("rsync"), "Workspace integration requires rsync (provided by macOS)")
class WorkspaceTests(unittest.TestCase):
    def test_cache_reuses_rust_outputs_and_invalidates_changed_sources(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source, cache = root / "checkout", root / "cache"
            (source / "tools/src").mkdir(parents=True)
            subprocess.run(["git", "init", "--quiet", str(source)], check=True)
            (source / "tools/Cargo.toml").write_text(
                '[package]\nname = "cache-probe"\nversion = "0.1.0"\nedition = "2021"\n')
            rust = source / "tools/src/main.rs"
            rust.write_text('fn main() { println!("first"); }\n')
            workspace = prepare(source, cache)
            env = {key: value for key, value in os.environ.items() if key != "CARGO_TARGET_DIR"}

            def build():
                return subprocess.run(["cargo", "build", "--offline", "--verbose"],
                                      cwd=workspace / "tools", env=env, check=True,
                                      capture_output=True, text=True).stderr

            self.assertIn("Compiling cache-probe", build())
            cached_source = workspace / "tools/src/main.rs"
            before = cached_source.stat().st_mtime_ns
            # Fresh checkouts have fresh mtimes even when file content is identical.
            os.utime(rust, ns=(before + 10_000_000_000, before + 10_000_000_000))
            stale = workspace / "removed.txt"
            stale.write_text("stale source")
            workspace = prepare(source, cache)
            self.assertEqual(cached_source.stat().st_mtime_ns, before)
            self.assertFalse(stale.exists())
            self.assertIn("Fresh cache-probe", build())
            rust.write_text('fn main() { println!("second"); }\n')
            workspace = prepare(source, cache)
            self.assertIn("Compiling cache-probe", build())
            binary = workspace / "tools/target/debug/cache-probe"
            self.assertEqual(subprocess.check_output([str(binary)], text=True).strip(), "second")

    def test_removed_files_disappear_but_both_cargo_target_caches_survive(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "checkout"
            source.mkdir()
            subprocess.run(["git", "init", "--quiet", str(source)], check=True)
            for path in ("tools", "src/eigin_sdk"):
                (source / path).mkdir(parents=True)
                (source / path / "Cargo.toml").write_text("fixture")
            workspace = prepare(source, root / "cache")
            for path in ("tools/target", "src/eigin_sdk/target"):
                (workspace / path).mkdir()
                (workspace / path / "artifact").write_text("compiled")
            (workspace / ".env").write_text("stale config")
            prepare(source, root / "cache")
            self.assertFalse((workspace / ".env").exists())
            for path in ("tools/target", "src/eigin_sdk/target"):
                self.assertEqual((workspace / path / "artifact").read_text(), "compiled")

    def test_nested_paths_are_rejected_before_sync(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            with self.assertRaises(ValueError):
                prepare(root, root / "cache")
            with self.assertRaises(ValueError):
                prepare(root / "checkout", root)


if __name__ == "__main__":
    unittest.main()
