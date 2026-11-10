"""Prepare stable source paths and preserve unchanged Cargo inputs across jobs."""

from pathlib import Path
import subprocess


def prepare(source, cache):
    """Sync the clean checkout while retaining compiled Rust targets and source mtimes."""
    source, cache = Path(source).resolve(), Path(cache).resolve()
    if cache.is_relative_to(source) or source.is_relative_to(cache):
        raise ValueError("iOS cache and checkout must be separate directories")
    workspace = cache / "workspace"
    workspace.mkdir(parents=True, exist_ok=True)
    # Omit --times: unchanged content keeps its cached mtime for Cargo fingerprints.
    subprocess.run([
        "rsync", "--recursive", "--links", "--perms", "--checksum", "--delete",
        "--exclude=/.git", "--exclude=/tools/target", "--exclude=/src/eigin_sdk/target",
        "--exclude=/src/eigin_ios/DerivedData", "--exclude=/logs",
        f"{source}/", f"{workspace}/",
    ], check=True)
    metadata = workspace / ".git"
    metadata.unlink(missing_ok=True)
    metadata.symlink_to(source / ".git", target_is_directory=True)
    actual = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], cwd=workspace, text=True)
    if Path(actual.strip()).resolve() != workspace:
        raise RuntimeError("Git did not resolve the stable iOS workspace")
    return workspace
