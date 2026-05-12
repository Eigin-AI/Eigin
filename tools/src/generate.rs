use anyhow::{Context, Result};
use std::process::Command;

use crate::config;
use crate::design;
use crate::localize;

/// Run all code generation tasks for the project.
///
/// - iOS: generates the Xcode project from project.yml via xcodegen,
///   then updates the build server config for IDE/LSP support.
/// - All platforms: generates localization source files from catalog.
#[derive(clap::Args)]
pub struct GenerateArgs {}

pub fn run(_args: GenerateArgs) -> Result<()> {
    let root = config::repo_root()?;
    let ios_dir = format!("{root}/src/eigin_ios");

    // Run all codegen before xcodegen so generated files are on disk
    // when xcodegen scans the source directories.
    localize::generate_all(&root)?;
    design::generate_all(&root)?;

    run_cmd(
        Command::new("xcodegen")
            .arg("generate")
            .current_dir(&ios_dir),
        "xcodegen generate",
    )?;

    run_cmd(
        Command::new("xcode-build-server")
            .args([
                "config",
                "-project",
                "Eigin-iOS.xcodeproj",
                "-scheme",
                "Eigin",
            ])
            .current_dir(&ios_dir),
        "xcode-build-server config",
    )?;

    Ok(())
}

fn run_cmd(cmd: &mut Command, label: &str) -> Result<()> {
    let status = cmd.status().with_context(|| format!("running {label}"))?;
    if !status.success() {
        anyhow::bail!("{label} failed");
    }
    Ok(())
}
