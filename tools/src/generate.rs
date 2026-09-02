use anyhow::{Context, Result};
use std::process::Command;

use crate::codegen;
use crate::config;
use crate::design;
use crate::knowledge;
use crate::localize;
use crate::prompts;

/// Run all code generation tasks for the project.
///
/// - Always: localization, design tokens, prompts and knowledge.
/// - With xcodegen installed: the Xcode project from project.yml. xcodegen
///   itself doesn't need Xcode, only the Swift runtime.
/// - With Xcode available: the build server config for IDE/LSP support.
///
/// Each Xcode step is skipped with a note when its tool is absent, so relay and
/// tooling work needs only Rust.
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

    if !is_installed("xcodegen") {
        println!("Skipping the Xcode project: xcodegen not installed (needed for iOS work).");
        return Ok(());
    }

    run_cmd(
        Command::new("xcodegen")
            .arg("generate")
            .env("BUNDLE_ID", bundle_id(&root)?)
            .current_dir(&ios_dir),
        "xcodegen generate",
    )?;

    // IDE/LSP convenience only, and the one step that genuinely needs Xcode.
    if !is_installed("xcodebuild") || !is_installed("xcode-build-server") {
        println!("Skipping the build server config: needs Xcode and xcode-build-server.");
        return Ok(());
    }

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

/// Bundle identifier for the generated project, from `config/app.toml`.
fn bundle_id(root: &str) -> Result<String> {
    Ok(config::load(root)?.app.identity.bundle_id)
}

/// Whether a command can be run, used to skip steps whose tool is absent.
fn is_installed(name: &str) -> bool {
    Command::new(name)
        .arg("--version")
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .is_ok()
}

fn run_cmd(cmd: &mut Command, label: &str) -> Result<()> {
    let status = cmd.status().with_context(|| format!("running {label}"))?;
    if !status.success() {
        anyhow::bail!("{label} failed");
    }
    Ok(())
}
