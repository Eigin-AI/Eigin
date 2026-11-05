"""Small standard-library helpers for CI command execution and downloads."""

import hashlib
import shutil
from pathlib import Path
import subprocess
import tarfile
import time


def run(*args, **kwargs):
    """Run a command and stop on failure."""
    return subprocess.run(args, check=True, **kwargs)


def download(url, path, checksum=None):
    """Download over HTTPS and optionally verify the archive before use."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        temporary = path.with_suffix(path.suffix + ".part")
        try:
            run("curl", "--fail", "--silent", "--show-error", "--location",
                "--proto", "=https", url, "-o", str(temporary))
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)
    if checksum and hashlib.sha256(path.read_bytes()).hexdigest() != checksum:
        path.unlink()
        raise ValueError("Download checksum mismatch")


def extract(archive, destination):
    """Extract tool files and internal symlinks without trusting archive paths."""
    root = Path(destination).resolve()
    root.mkdir(parents=True, exist_ok=True)

    def contained(path):
        if not path.resolve().is_relative_to(root):
            raise ValueError("Archive path escapes destination")
        return path

    with tarfile.open(archive) as tar:
        for member in tar:
            if Path(member.name).is_absolute():
                raise ValueError("Absolute archive path")
            path = contained(root / member.name)
            if member.isdir():
                path.mkdir(parents=True, exist_ok=True)
                continue
            if not (member.isfile() or member.issym()):
                raise ValueError("Unsupported archive entry")
            path.parent.mkdir(parents=True, exist_ok=True)
            if path.is_symlink():
                raise ValueError("Archive entry overwrites a symlink")
            if member.issym():
                if Path(member.linkname).is_absolute():
                    raise ValueError("Absolute archive link")
                contained(path.parent / member.linkname)
                path.symlink_to(member.linkname)
            else:
                with tar.extractfile(member) as source, path.open("wb") as target:
                    shutil.copyfileobj(source, target)
                path.chmod(member.mode & 0o777)


def phase(label, action):
    """Print a CI group and duration, including for failed commands."""
    print(f"--- {label}", flush=True)
    start = time.monotonic()
    try:
        action()
    finally:
        print(f"Duration: {label}: {time.monotonic() - start:.1f}s", flush=True)
