use anyhow::{Context, Result};
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::process::Command;

pub fn run() -> Result<()> {
    let root = repo_root()?;
    let hooks_dir = format!("{root}/.git/hooks");
    let manifest = format!("{root}/tools/Cargo.toml");

    write_hook(
        &format!("{hooks_dir}/pre-commit"),
        &format!(
            "#!/bin/sh\nexec \"$HOME/.cargo/bin/cargo\" run --quiet --manifest-path \"{manifest}\" -- hooks pre-commit\n"
        ),
    )?;

    write_hook(
        &format!("{hooks_dir}/commit-msg"),
        &format!(
            "#!/bin/sh\nexec \"$HOME/.cargo/bin/cargo\" run --quiet --manifest-path \"{manifest}\" -- hooks commit-msg \"$1\"\n"
        ),
    )?;

    println!("✓ Hooks installed.");
    Ok(())
}

fn write_hook(path: &str, content: &str) -> Result<()> {
    // Remove any existing file or dangling symlink before writing.
    let _ = fs::remove_file(path);
    fs::write(path, content).with_context(|| format!("writing hook {path}"))?;
    fs::set_permissions(path, fs::Permissions::from_mode(0o755))
        .with_context(|| format!("setting permissions on {path}"))?;
    Ok(())
}

fn repo_root() -> Result<String> {
    let out = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .context("running git rev-parse --show-toplevel")?;
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}
