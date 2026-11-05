#!/usr/bin/env python3
"""Build docs with verified licensed fonts."""

import os
from pathlib import Path
import sys
import tempfile

from ci_tools import download, extract, run


def main():
    """Install mdBook tools, fetch fonts, and generate the book."""
    with tempfile.TemporaryDirectory() as tools:
        for name, repo, version in (("mdbook", "rust-lang/mdBook", "0.5.3"),
                                    ("mdbook-mermaid", "badboy/mdbook-mermaid", "0.17.0")):
            archive = Path(tools) / f"{name}.tar.gz"
            download(f"https://github.com/{repo}/releases/download/v{version}/{name}-v{version}-x86_64-unknown-linux-musl.tar.gz", archive)
            extract(archive, tools)
        os.environ["PATH"] = f"{tools}:{os.environ['PATH']}"
        os.environ.update(CI_API_V4_URL="https://code.eigin.ai/api/v4", CI_PROJECT_ID="2")
        run(sys.executable, ".buildkite/scripts/download-docs-fonts.py")
        run("cargo", "run", "--locked", "--manifest-path", "tools/Cargo.toml", "--", "generate", "docs")
        run("mdbook", "build", "docs/")


if __name__ == "__main__":
    main()
