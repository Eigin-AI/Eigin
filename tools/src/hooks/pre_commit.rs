use anyhow::{Context, Result};
use std::process::Command;

/// Run all pre-commit checks.
///
/// - Swift: lints staged .swift files with swiftformat.
/// - Rust: checks formatting with cargo fmt if any .rs files are staged.
pub fn run() -> Result<()> {
    check_swift()?;
    check_rust()?;
    Ok(())
}

fn check_swift() -> Result<()> {
    let staged = staged_files("*.swift")?;
    if staged.is_empty() {
        return Ok(());
    }

    if !command_available("swiftformat") {
        eprintln!("warning: swiftformat not found, skipping Swift format check");
        return Ok(());
    }

    let status = Command::new("swiftformat")
        .args(["--lint", "--quiet"])
        .args(&staged)
        .status()
        .context("running swiftformat")?;

    if !status.success() {
        eprintln!();
        eprintln!("Swift format violations found. Run 'format' to fix.");
        std::process::exit(1);
    }

    Ok(())
}

fn check_rust() -> Result<()> {
    let staged = staged_files("*.rs")?;
    if staged.is_empty() {
        return Ok(());
    }

    let repo_root = repo_root()?;

    for manifest in &[
        format!("{repo_root}/src/eigin_relay/Cargo.toml"),
        format!("{repo_root}/tools/Cargo.toml"),
    ] {
        let status = Command::new("cargo")
            .args(["fmt", "--manifest-path", manifest, "--", "--check"])
            .status()
            .context("running cargo fmt")?;

        if !status.success() {
            eprintln!();
            eprintln!("Rust format violations found. Run 'format' to fix.");
            std::process::exit(1);
        }
    }

    Ok(())
}

fn staged_files(pattern: &str) -> Result<Vec<String>> {
    let out = Command::new("git")
        .args([
            "diff",
            "--cached",
            "--name-only",
            "--diff-filter=ACM",
            "--",
            pattern,
        ])
        .output()
        .context("running git diff")?;

    Ok(String::from_utf8_lossy(&out.stdout)
        .lines()
        .filter(|l| !l.is_empty())
        .map(String::from)
        .collect())
}

fn repo_root() -> Result<String> {
    let out = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .context("running git rev-parse")?;
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

fn command_available(cmd: &str) -> bool {
    Command::new(cmd)
        .arg("--version")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}
