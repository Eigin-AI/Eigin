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
    credential = "DOCS_GITLAB_TOKEN" if os.environ.get("DOCS_GITLAB_TOKEN") else "CI_JOB_TOKEN"
    token = os.environ.get(credential)
    if not token:
        raise SystemExit("Secure Files require DOCS_GITLAB_TOKEN or CI_JOB_TOKEN")
    header_name = "PRIVATE-TOKEN" if credential == "DOCS_GITLAB_TOKEN" else "JOB-TOKEN"
    header = f"{header_name}: {token}"
    api = f"{os.environ['CI_API_V4_URL']}/projects/{os.environ['CI_PROJECT_ID']}/secure_files"

    def fetch(url, operation):
        with tempfile.TemporaryDirectory() as directory:
            response = Path(directory) / "response"
            result = subprocess.run([
                "curl", "--silent", "--show-error", "--proto", "=https",
                "--header", header, "--output", str(response),
                "--write-out", "%{http_code}", url,
            ], capture_output=True, text=True)
            context = f"Secure Files: {operation} using {credential}"
            if result.returncode:
                raise SystemExit(f"{context} failed (curl exit {result.returncode})")
            status = result.stdout.strip()
            if status != "200":
                detail = ""
                try:
                    body = json.loads(response.read_bytes())
                    if isinstance(body, dict):
                        message = body.get("message") or body.get("error")
                        if isinstance(message, str):
                            for name in ("DOCS_GITLAB_TOKEN", "CI_JOB_TOKEN"):
                                secret = os.environ.get(name)
                                if secret:
                                    message = message.replace(secret, "[redacted]")
                            detail = f": {json.dumps(message[:500])}"
                except (ValueError, OSError):
                    pass
                raise SystemExit(f"{context} failed (HTTP {status}){detail}")
            return response.read_bytes()

    files = json.loads(fetch(f"{api}?per_page=100", "list files"))
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
            data = fetch(f"{api}/{matches[0]['id']}/download", f"download {name}")
            if hashlib.sha256(data).hexdigest() != checksum:
                raise ValueError(f"Docs font checksum mismatch: {name}")
            (Path(temporary) / name).write_bytes(data)
        for name in manifest:
            (destination / name).write_bytes((Path(temporary) / name).read_bytes())


if __name__ == "__main__":
    main()
