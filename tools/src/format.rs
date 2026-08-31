use anyhow::{Context, Result};
use std::process::Command;

/// Format all code in the repo.
///
/// - Swift: runs swiftformat on iOS sources, tests, and scripts.
/// - Rust: runs cargo fmt on the relay and tools crates.
#[derive(clap::Args)]
pub struct FormatArgs {}

pub fn run(_args: FormatArgs) -> Result<()> {
    let root = repo_root()?;
    let ios = format!("{root}/src/eigin_ios");

    run_cmd(
        Command::new("swiftformat")
            .arg(format!("{ios}/Sources"))
            .arg(format!("{ios}/Tests"))
            .arg(format!("{ios}/Widgets")),
        "swiftformat",
    )?;

    run_cmd(
        Command::new("cargo").args([
            "fmt",
            "--manifest-path",
            &format!("{root}/src/eigin_relay/Cargo.toml"),
        ]),
        "cargo fmt (relay)",
    )?;

    run_cmd(
        Command::new("cargo").args([
            "fmt",
            "--manifest-path",
            &format!("{root}/tools/Cargo.toml"),
        ]),
        "cargo fmt (tools)",
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

fn repo_root() -> Result<String> {
    let out = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .context("running git rev-parse")?;
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}
