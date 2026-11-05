#!/usr/bin/env python3
"""Publish the current main commit; Buildkite serializes uploads."""

import os
from pathlib import Path
import tempfile

from ci_tools import download, run


def main():
    """Validate build context and sync a nonempty book to the docs bucket."""
    env = os.environ
    if (env.get("BUILDKITE_BRANCH") != "main" or
            env.get("BUILDKITE_PULL_REQUEST", "false") != "false" or
            env.get("BUILDKITE_SOURCE") != "webhook"):
        raise SystemExit("Docs publishing requires a main webhook build without an MR.")
    for key in ("BUILDKITE_COMMIT", "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"):
        if not env.get(key):
            raise SystemExit(f"Required: {key}")
    head = run("git", "ls-remote", "https://code.eigin.ai/dev/eigin.git", "refs/heads/main",
               capture_output=True, text=True).stdout.split()
    if not head:
        raise SystemExit("Could not determine main HEAD")
    if head[0] != env["BUILDKITE_COMMIT"]:
        print("Skipping stale docs build: main has advanced.")
        return
    index = Path("docs/book/index.html")
    if not index.is_file() or not index.stat().st_size:
        raise SystemExit("Built docs index is missing or empty")
    with tempfile.TemporaryDirectory() as work:
        archive = Path(work) / "aws.zip"
        download("https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip", archive)
        run("unzip", "-q", str(archive), "-d", work)
        run(f"{work}/aws/install", "-b", f"{work}/bin", "-i", f"{work}/cli")
        run(f"{work}/bin/aws", "s3", "sync", "docs/book/", "s3://eigin-docs/",
            "--endpoint-url", "https://s3.fr-par.scw.cloud", "--delete")


if __name__ == "__main__":
    main()
