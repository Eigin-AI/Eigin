#!/usr/bin/env python3
"""Run version checks and integration tests using cached, verified tooling."""

import os
from pathlib import Path
import tempfile
import sys

from ci_tools import download, extract, phase, run

NODE = "22.23.4"
NODE_SHA = "1805bcd35e6815559bd2eb97db438d3fdb0eb3a5e6a977b7c1badca76337e9ce"
JUST_SHA = "409044617b6f06517c1035e55ca38c8c856ff8b650e41bc2aa1ef82d5903a23e"


def install_node(destination):
    """Verify the cached Node distribution and expose its bundled npm."""
    archive = Path(os.environ.get("CARGO_HOME", "/tmp/eigin-cargo")) / "downloads" / f"node-v{NODE}-linux-x64.tar.xz"
    download(f"https://nodejs.org/dist/v{NODE}/{archive.name}", archive, NODE_SHA)
    extract(archive, destination)
    os.environ["PATH"] = f"{destination}/node-v{NODE}-linux-x64/bin:{os.environ['PATH']}"


def install_just(destination):
    """Install a verified prebuilt just release."""
    archive = Path(destination) / "just.tar.gz"
    download("https://github.com/casey/just/releases/download/1.59.0/just-1.59.0-x86_64-unknown-linux-musl.tar.gz", archive, JUST_SHA)
    extract(archive, destination)
    os.environ["PATH"] = f"{destination}:{os.environ['PATH']}"


def main():
    """Install tools and run all checks, stopping at the first failure."""
    print(f"Python {sys.version.split()[0]}", flush=True)
    with tempfile.TemporaryDirectory() as tools:
        phase(f"Install Node {NODE} and npm", lambda: install_node(tools))
        phase("Install just 1.59.0", lambda: install_just(tools))
        phase("Version check", lambda: run("cargo", "run", "--locked", "--manifest-path", "tools/Cargo.toml", "--", "version", "check"))
        for suite in ("version", "releases"):
            phase(f"{suite.title()} tests", lambda: run("cargo", "test", "--locked", "--manifest-path", "tools/Cargo.toml", "--test", suite))


if __name__ == "__main__":
    main()
