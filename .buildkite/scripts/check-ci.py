#!/usr/bin/env python3
"""Run CI regression tests with verified YAML parsing and recipe tooling."""

import importlib.util
import os
from pathlib import Path
import platform
import shutil
import sys
import tempfile

from ci_tools import download, extract, run

YAML_URL = "https://files.pythonhosted.org/packages/05/8e/961c0007c59b8dd7729d542c61a4d537767a59645b82a0b521206e1e25c2/pyyaml-6.0.3.tar.gz"
YAML_SHA = "d76623373421df22fb4cf8817020cbb7ef15c725b9d5e45f17e189bfc384190f"


def main():
    """Install isolated test dependencies, then execute every CI regression test."""
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        archive = root / "pyyaml.tar.gz"
        download(YAML_URL, archive, YAML_SHA)
        extract(archive, root)
        os.environ["PYTHONPATH"] = str(root / "pyyaml-6.0.3/lib")
        os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
        if platform.system() == "Linux" and platform.machine() == "x86_64":
            spec = importlib.util.spec_from_file_location("versions", Path(__file__).with_name("check-versions.py"))
            versions = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(versions)
            versions.install_just(root / "just")
        elif not shutil.which("just"):
            raise RuntimeError("Install just 1.59.0 before running CI tests on this platform")
        run(sys.executable, "-m", "unittest", "discover", "-s", ".buildkite/tests")


if __name__ == "__main__":
    main()
