use super::run;
use anyhow::{Context, Result};
use std::{
    fs,
    path::{Path, PathBuf},
    process::Command,
};

/// Cache the rewriter matching the SDK's locked wasm-bindgen runtime.
pub(crate) fn ensure(root: &str) -> Result<PathBuf> {
    // The binding generator validates explicit tool overrides against the WASM artifact.
    if let Some(path) = std::env::var_os("UBRN_WASM_BINDGEN") {
        return Ok(PathBuf::from(path));
    }
    let lock = fs::read_to_string(format!("{root}/src/eigin_sdk/Cargo.lock"))?;
    let version = locked_version(&lock)?;

    let cache = Path::new(root).join("src/eigin_sdk/target/wasm-bindgen-tools");
    let executable = cache
        .join("bin")
        .join(format!("wasm-bindgen{}", std::env::consts::EXE_SUFFIX));
    if !matches_version(&executable, &version) {
        run(Command::new("cargo")
            .args([
                "install",
                "wasm-bindgen-cli",
                "--version",
                &version,
                "--locked",
                "--root",
            ])
            .arg(&cache)
            .current_dir(format!("{root}/src/eigin_sdk")))?;
    }
    Ok(executable)
}

fn matches_version(path: &Path, version: &str) -> bool {
    Command::new(path)
        .arg("--version")
        .output()
        .is_ok_and(|output| {
            output.status.success()
                && String::from_utf8_lossy(&output.stdout).trim()
                    == format!("wasm-bindgen {version}")
        })
}

fn locked_version(lock: &str) -> Result<String> {
    let document: toml::Value = toml::from_str(lock)?;
    document
        .get("package")
        .and_then(toml::Value::as_array)
        .and_then(|packages| {
            packages
                .iter()
                .find(|package| package["name"].as_str() == Some("wasm-bindgen"))
        })
        .and_then(|package| package["version"].as_str())
        .map(str::to_owned)
        .context("SDK lockfile has no wasm-bindgen version")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn selects_runtime_version_instead_of_macro_version() {
        let lock = "[[package]]\nname = 'wasm-bindgen-macro'\nversion = '1.0.0'\n[[package]]\nname = 'wasm-bindgen'\nversion = '0.2.130'";
        assert_eq!(locked_version(lock).unwrap(), "0.2.130");
        assert!(locked_version("[[package]]\nname = 'another-crate'\nversion = '1.0.0'").is_err());
    }
}
