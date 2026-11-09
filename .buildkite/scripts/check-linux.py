"""Run current Rust component suites inside the pinned Linux toolchain image."""

import sys

from ci_tools import phase, run

SDK = "src/eigin_sdk/Cargo.toml"
RELAY = "src/eigin_relay/Cargo.toml"


def commands(component):
    """Return the existing suite contract, with locked dependency resolution."""
    if component == "relay":
        return [["cargo", "test", "--locked", "--manifest-path", RELAY]]
    if component == "postgres":
        return [["cargo", "test", "--locked", "--manifest-path", RELAY,
                 "--", "--ignored", "--nocapture"]]
    if component != "sdk":
        raise ValueError("Unknown Linux component")
    build = ["cargo", "+1.99.1", "build", "--locked", "--manifest-path", SDK, "-p", "eigin_sdk"]
    return [
        ["rustup", "component", "add", "--toolchain", "1.99.1", "rustfmt", "clippy"],
        ["rustup", "target", "add", "--toolchain", "1.99.1", "wasm32-unknown-unknown"],
        build,
        [*build, "--target", "wasm32-unknown-unknown"],
        ["cargo", "+1.99.1", "test", "--locked", "--manifest-path", SDK, "--features", "binding-tests"],
        ["cargo", "+1.99.1", "clippy", "--locked", "--manifest-path", SDK, "--all-targets", "--", "-D", "warnings"],
        ["cargo", "+1.99.1", "fmt", "--manifest-path", SDK, "--all", "--", "--check"],
    ]


def main(component):
    """Stop immediately on setup or suite failure and print phase timings."""
    for command in commands(component):
        phase(" ".join(command), lambda command=command: run(*command))


if __name__ == "__main__":
    main(sys.argv[1])
