#!/usr/bin/env python3
"""Run the local iOS suite with selected hosted tools and retained reports."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import zipfile

from ci_tools import download, extract, run
from ios_workspace import prepare

XCODE = "26.2"
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-26-2"
DEVICE = "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
JUST_SHA = "6574cea774ed4cae12e24b6aa11857de33e80dab4667cf628fd5840df96a2a9d"
XCODEGEN_SHA = "4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806"


def output(*args):
    """Capture a successful command's text output."""
    return subprocess.check_output(args, text=True).strip()


def select_xcode():
    """Select an installed stable Xcode explicitly, never the queue default."""
    for app in sorted(Path("/Applications").glob("Xcode*.app")):
        developer = app / "Contents/Developer"
        try:
            version = subprocess.check_output(
                ["xcodebuild", "-version"], text=True,
                env={**os.environ, "DEVELOPER_DIR": str(developer)},
            ).strip()
        except subprocess.CalledProcessError:
            continue
        if version == f"Xcode {XCODE}\nBuild version 17C52":
            os.environ["DEVELOPER_DIR"] = str(developer)
            print(version, flush=True)
            return
    raise RuntimeError(f"macos-medium must include Xcode {XCODE}")


def install_tools(cache, destination):
    """Install checksum-verified generation tools into a fresh job directory."""
    just = cache / "just-1.59.0-arm64.tar.gz"
    download("https://github.com/casey/just/releases/download/1.59.0/just-1.59.0-aarch64-apple-darwin.tar.gz", just, JUST_SHA)
    extract(just, destination)
    archive = cache / "xcodegen-2.46.0.zip"
    download("https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip", archive, XCODEGEN_SHA)
    # The checksum pins the archive; still reject paths outside the tool directory.
    with zipfile.ZipFile(archive) as bundle:
        for member in bundle.infolist():
            if not (destination / member.filename).resolve().is_relative_to(destination.resolve()):
                raise ValueError("Unsafe XcodeGen archive path")
        bundle.extractall(destination)
    (destination / "xcodegen/bin/xcodegen").chmod(0o755)
    os.environ["PATH"] = f"{destination}:{destination}/xcodegen/bin:{os.environ['PATH']}"
    if output("just", "--version") != "just 1.59.0":
        raise RuntimeError("Expected just 1.59.0")
    if output("xcodegen", "--version") != "Version: 2.46.0":
        raise RuntimeError("Expected XcodeGen 2.46.0")
    if output("swiftformat", "--version") != "0.64.5":
        raise RuntimeError("Expected SwiftFormat 0.64.5 in macos-medium")
    run("rustup", "toolchain", "install", "1.99.1", "--profile", "minimal")
    os.environ["RUSTUP_TOOLCHAIN"] = "1.99.1"
    print(output("rustc", "--version"), flush=True)


def validate_runtimes(data):
    """Require the selected iOS and watchOS simulator runtimes."""
    available = {r["identifier"] for r in data["runtimes"] if r.get("isAvailable")}
    required = {RUNTIME, "com.apple.CoreSimulator.SimRuntime.watchOS-26-2"}
    if not required <= available:
        raise RuntimeError(f"Missing simulator runtimes: {sorted(required - available)}")


def reports(bundle, directory):
    """Retain the raw bundle and produce a readable result summary."""
    if not bundle.exists():
        return
    with tarfile.open(directory / "tests.xcresult.tar.gz", "w:gz") as archive:
        archive.add(bundle, arcname=bundle.name)
    summary = output("xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(bundle))
    data = json.loads(summary)
    (directory / "summary.json").write_text(json.dumps(data, indent=2) + "\n")
    text = "\n".join(f"{key}: {data.get(key, 'unknown')}" for key in
                     ("title", "result", "totalTestCount", "passedTests", "failedTests", "skippedTests"))
    (directory / "summary.txt").write_text(text + "\n")
    print(text, flush=True)


def main():
    """Build/test with simulator identity and retain diagnostics, including on test failure."""
    directory = Path("logs/ios-ci").resolve()
    directory.mkdir(parents=True, exist_ok=True)
    cache = Path(os.environ.get("IOS_CACHE_DIR", str(Path.home() / ".cache/eigin-ios")))
    cache.mkdir(parents=True, exist_ok=True)
    os.environ["CARGO_HOME"] = str(cache / "cargo")
    if Path(".env").exists():
        raise RuntimeError("CI expects a clean checkout without .env")
    simulator = None
    checkout = None
    with tempfile.TemporaryDirectory() as temporary:
        workspace = Path(temporary)
        bundle = workspace / "tests.xcresult"
        status = 1
        try:
            select_xcode()
            install_tools(cache, workspace / "tools")
            checkout = prepare(Path.cwd(), cache)
            os.environ.pop("CARGO_TARGET_DIR", None)
            runtime_data = json.loads(output("xcrun", "simctl", "list", "runtimes", "--json"))
            validate_runtimes(runtime_data)
            (directory / "runtimes.json").write_text(json.dumps(runtime_data, indent=2) + "\n")
            (directory / "toolchain.txt").write_text(output("xcodebuild", "-version") + "\n" + output("rustc", "--version") + "\n")
            simulator = output("xcrun", "simctl", "create", "Eigin CI", DEVICE, RUNTIME)
            os.environ.update(IOS_TEST_DESTINATION=f"platform=iOS Simulator,id={simulator}",
                              IOS_TEST_RESULT_BUNDLE=str(bundle), IOS_TEST_AD_HOC_SIGNING="true",
                              IOS_TEST_PACKAGES=str(cache / "swift-packages"),
                              IOS_TEST_DERIVED_DATA=str(workspace / "DerivedData"))
            with (directory / "test.log").open("w") as log:
                process = subprocess.Popen(["just", "test", "ios", "--verbose"], stdout=subprocess.PIPE,
                                           stderr=subprocess.STDOUT, text=True, cwd=checkout)
                for line in process.stdout:
                    print(line, end="", flush=True)
                    log.write(line)
                status = process.wait()
            resolved = checkout / "src/eigin_ios/Eigin-iOS.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
            if resolved.exists():
                (directory / "Package.resolved").write_bytes(resolved.read_bytes())
            try:
                reports(bundle, directory)
            except Exception as error:
                print(f"Report generation failed: {error}", file=sys.stderr)
                status = status or 1
            return status
        finally:
            if checkout:
                (checkout / ".git").unlink(missing_ok=True)
            if simulator:
                subprocess.run(["xcrun", "simctl", "delete", simulator], check=False)


if __name__ == "__main__":
    sys.exit(main())
