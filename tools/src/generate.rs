use anyhow::{Context, Result};
use std::env;
use std::process::Command;

use crate::codegen;
use crate::config;
use crate::design;
use crate::knowledge;
use crate::localize;
use crate::prompts;

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
    prompts::generate_all(&root)?;
    knowledge::generate_all(&root)?;

    // The prompt and knowledge registries used to be generated into the design
    // folder. They are gitignored, so a checkout predating the move keeps the
    // old copies and the widget extension — which compiles Design/Generated —
    // fails on the duplicate filenames.
    codegen::remove_stale_duplicates(
        &format!("{ios_dir}/Sources/Core/Content/Generated"),
        &format!("{ios_dir}/Sources/Core/Design/Generated"),
    )?;

    run_cmd(
        Command::new("xcodegen")
            .arg("generate")
            .env("BUNDLE_ID", bundle_id())
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

/// Bundle identifier for the generated project. Without one the app builds but
/// can't be installed, so environments with no `.env` (worktrees, OSS clones)
/// fall back to the default identifier.
fn bundle_id() -> String {
    match env::var("BUNDLE_ID") {
        Ok(id) if !id.trim().is_empty() => id,
        _ => "ai.eigin.finch".to_string(),
    }
}

fn run_cmd(cmd: &mut Command, label: &str) -> Result<()> {
    let status = cmd.status().with_context(|| format!("running {label}"))?;
    if !status.success() {
        anyhow::bail!("{label} failed");
    }
    Ok(())
}
