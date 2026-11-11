//! Reproducible SDK bindings and local artifacts.

use anyhow::{Context, Result, bail};
use std::fs;
use std::path::Path;
use std::process::Command;

mod apple;
pub mod notices;

/// Independently selectable SDK host artifacts.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, clap::ValueEnum)]
pub enum SdkTarget {
    #[default]
    All,
    Apple,
    Web,
}

/// Generate SDK host artifacts without loading application configuration.
pub fn generate(root: &str, target: SdkTarget) -> Result<()> {
    ensure_web_dependencies(root)?;
    notices::generate(root, false)?;
    if matches!(target, SdkTarget::Web | SdkTarget::All) {
        web(root)?;
    }
    if matches!(target, SdkTarget::Apple | SdkTarget::All) {
        apple::generate(root)?;
    }
    Ok(())
}

fn web(root: &str) -> Result<()> {
    ensure_web_dependencies(root)?;
    let cli = Path::new(root).join("node_modules/.bin/ubrn");
    let staging = format!("{root}/src/eigin_sdk/target/web-bindings");
    if Path::new(&staging).exists() {
        fs::remove_dir_all(&staging)?;
    }
    run(Command::new(cli)
        .args([
            "build",
            "wasm2",
            "--config",
            "ubrn.config.yaml",
            "--release",
        ])
        .current_dir(format!("{root}/src/eigin_sdk/web")))?;
    sync_generated(
        Path::new(&staging),
        Path::new(&format!("{root}/src/eigin_sdk/web/src/generated")),
    )
}

/// Restore missing web tooling from the shared lockfile.
pub(crate) fn ensure_web_dependencies(root: &str) -> Result<()> {
    let modules = Path::new(root).join("node_modules/.bin");
    if modules.join("ubrn").exists() && modules.join("vite").exists() {
        return Ok(());
    }
    run(Command::new("npm")
        .args(["ci", "--no-fund", "--no-audit"])
        .current_dir(root))
}

fn copy_if_changed(source: &Path, destination: &Path) -> Result<()> {
    if fs::read(destination).ok().as_deref() != Some(fs::read(source)?.as_slice()) {
        fs::copy(source, destination)?;
    }
    Ok(())
}

/// Synchronize a dedicated generated tree while preserving unchanged file timestamps.
fn sync_generated(source: &Path, destination: &Path) -> Result<()> {
    fs::create_dir_all(destination)?;
    for entry in fs::read_dir(destination)? {
        let entry = entry?;
        if !source.join(entry.file_name()).exists() {
            if entry.file_type()?.is_dir() {
                fs::remove_dir_all(entry.path())?;
            } else {
                fs::remove_file(entry.path())?;
            }
        }
    }
    for entry in fs::read_dir(source)? {
        let entry = entry?;
        let target = destination.join(entry.file_name());
        if entry.file_type()?.is_dir() {
            sync_generated(&entry.path(), &target)?;
        } else {
            copy_if_changed(&entry.path(), &target)?;
        }
    }
    Ok(())
}

pub(crate) fn run(command: &mut Command) -> Result<()> {
    // Respect the SDK toolchain file when launched through the repository tools crate.
    command.env_remove("RUSTUP_TOOLCHAIN");
    let status = command
        .status()
        .with_context(|| format!("running {command:?}"))?;
    if !status.success() {
        bail!("SDK command failed: {command:?}");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generated_sync_removes_stale_files_and_keeps_unchanged_outputs() {
        let root = tempfile::tempdir().unwrap();
        let source = root.path().join("source");
        let destination = root.path().join("generated");
        fs::create_dir_all(&source).unwrap();
        fs::create_dir_all(&destination).unwrap();
        fs::write(source.join("api.ts"), "current").unwrap();
        fs::write(destination.join("api.ts"), "current").unwrap();
        fs::write(destination.join("stale.ts"), "old").unwrap();
        let before = fs::metadata(destination.join("api.ts"))
            .unwrap()
            .modified()
            .unwrap();
        sync_generated(&source, &destination).unwrap();
        assert!(!destination.join("stale.ts").exists());
        assert_eq!(
            before,
            fs::metadata(destination.join("api.ts"))
                .unwrap()
                .modified()
                .unwrap()
        );
        fs::write(source.join("api.ts"), "updated").unwrap();
        sync_generated(&source, &destination).unwrap();
        assert_eq!(
            fs::read_to_string(destination.join("api.ts")).unwrap(),
            "updated"
        );
    }
}
