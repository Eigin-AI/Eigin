use anyhow::{Context, Result};
use std::process::Command;

use crate::{config, localize};

/// Lint all code in the repo without modifying files.
///
/// - Swift: runs swiftformat --lint on iOS sources, tests, and scripts.
/// - Rust: runs cargo fmt --check on the relay and tools crates.
/// - Web: runs prettier --check + eslint on design/web.
/// - Localization: validates that all String(localized:) keys exist in Localized.swift.
#[derive(clap::Args)]
pub struct LintArgs {}

pub fn run(_args: LintArgs) -> Result<()> {
    let root = repo_root()?;
    let ios = format!("{root}/src/eigin_ios");

    let mut failed = false;

    if !run_cmd(
        Command::new("swiftformat")
            .args(["--lint", "--quiet"])
            .arg(format!("{ios}/Sources"))
            .arg(format!("{ios}/Tests"))
            .arg(format!("{ios}/Widgets")),
        "swiftformat --lint",
    )? {
        failed = true;
    }

    for (manifest, label) in &[
        (
            format!("{root}/src/eigin_relay/Cargo.toml"),
            "cargo fmt --check (relay)",
        ),
        (
            format!("{root}/tools/Cargo.toml"),
            "cargo fmt --check (tools)",
        ),
    ] {
        if !run_cmd(
            Command::new("cargo").args(["fmt", "--manifest-path", manifest, "--", "--check"]),
            label,
        )? {
            failed = true;
        }
    }

    // Web: prettier --check + eslint. Skipped with a note without node_modules.
    let web = format!("{root}/design/web");
    if std::path::Path::new(&format!("{root}/node_modules")).is_dir() {
        if !run_cmd(
            Command::new("npx")
                .args(["prettier", "--check", "src", "tests"])
                .current_dir(&web),
            "prettier --check",
        )? {
            failed = true;
        }
        if !run_cmd(
            Command::new("npx").args(["eslint", "."]).current_dir(&web),
            "eslint",
        )? {
            failed = true;
        }
    } else {
        println!("Skipping web lint: root node_modules missing.");
    }

    if std::path::Path::new(&format!("{root}/node_modules")).is_dir()
        && !run_cmd(
            Command::new("npx")
                .args(["prettier", "--check", "."])
                .current_dir(format!("{root}/src/eigin_website")),
            "prettier --check (website)",
        )?
    {
        failed = true;
    }
    let root = config::repo_root()?;
    if !localize::validate_all(&root)? {
        failed = true;
    }

    if failed {
        anyhow::bail!("one or more lint checks failed");
    }

    Ok(())
}

/// Runs a command and returns Ok(true) on success, Ok(false) on non-zero exit.
fn run_cmd(cmd: &mut Command, label: &str) -> Result<bool> {
    let status = cmd.status().with_context(|| format!("running {label}"))?;
    Ok(status.success())
}

fn repo_root() -> Result<String> {
    let out = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .context("running git rev-parse")?;
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}
