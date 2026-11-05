#!/usr/bin/env python3
"""Download only manifest-listed GitLab Secure Files and verify their checksums."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


def main():
    """Stage verified fonts without logging private file contents or tokens."""
    root = Path.cwd()
    token = os.environ.get("DOCS_GITLAB_TOKEN")
    header = f"PRIVATE-TOKEN: {token}" if token else f"JOB-TOKEN: {os.environ['CI_JOB_TOKEN']}"
    api = f"{os.environ['CI_API_V4_URL']}/projects/{os.environ['CI_PROJECT_ID']}/secure_files"
    def fetch(url):
        return subprocess.check_output(["curl", "--fail", "--silent", "--show-error",
                                        "--proto", "=https", "--header", header, url])
    try:
        files = json.loads(fetch(f"{api}?per_page=100"))
        manifest = json.loads((root / "docs/fonts.json").read_text())
        destination = root / "design/assets/fonts/docs"
        destination.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory() as temporary:
            for name, checksum in manifest.items():
                if Path(name).name != name or name in (".", ".."):
                    raise ValueError("Invalid font filename")
                matches = [item for item in files if item.get("name") == name]
                if len(matches) != 1 or type(matches[0].get("id")) is not int:
                    raise ValueError(f"Missing or duplicate Secure File: {name}")
                data = fetch(f"{api}/{matches[0]['id']}/download")
                if hashlib.sha256(data).hexdigest() != checksum:
                    raise ValueError(f"Docs font checksum mismatch: {name}")
                (Path(temporary) / name).write_bytes(data)
            for name in manifest:
                (destination / name).write_bytes((Path(temporary) / name).read_bytes())
    except subprocess.CalledProcessError:
        raise SystemExit("Secure File request failed") from None


if __name__ == "__main__":
    main()
