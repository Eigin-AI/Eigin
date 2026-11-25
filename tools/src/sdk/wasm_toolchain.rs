//! Target-scoped C tooling for browser builds.

use anyhow::{Result, bail};
use std::{env, ffi::OsString, path::Path, process::Command};

/// Configure and run a WASM build without changing native compiler defaults.
pub(crate) fn run(command: &mut Command) -> Result<()> {
    let compiler = resolve("CC", "clang", |tool| {
        Command::new(tool)
            .arg("--print-targets")
            .output()
            .is_ok_and(|output| {
                output.status.success()
                    && String::from_utf8_lossy(&output.stdout).contains("wasm32")
            })
    })?;
    let archiver = resolve("AR", "llvm-ar", |tool| {
        Command::new(tool)
            .arg("--version")
            .output()
            .is_ok_and(|output| output.status.success())
    })?;
    super::run(
        command
            .env("CC_wasm32_unknown_unknown", compiler)
            .env("AR_wasm32_unknown_unknown", archiver),
    )
}

fn resolve(variable: &str, binary: &str, usable: impl Fn(&OsString) -> bool) -> Result<OsString> {
    for key in [
        format!("{variable}_wasm32-unknown-unknown"),
        format!("{variable}_wasm32_unknown_unknown"),
    ] {
        if let Some(tool) = env::var_os(&key) {
            if usable(&tool) {
                return Ok(tool);
            }
            bail!("{key}={tool:?} is not usable for WASM builds. Select LLVM {binary}.");
        }
    }
    let on_path = OsString::from(binary);
    if usable(&on_path) {
        return Ok(on_path);
    }
    if cfg!(target_os = "macos")
        && let Ok(output) = Command::new("brew").args(["--prefix", "llvm"]).output()
        && output.status.success()
    {
        let prefix = String::from_utf8_lossy(&output.stdout);
        let tool = Path::new(prefix.trim())
            .join("bin")
            .join(binary)
            .into_os_string();
        if usable(&tool) {
            return Ok(tool);
        }
    }
    bail!(
        "WASM builds require LLVM {binary} with WebAssembly support. Install `brew install llvm` on macOS or `apt-get install clang llvm` on Debian, or set {variable}_wasm32_unknown_unknown to a compatible executable. See src/eigin_sdk/README.md."
    )
}
