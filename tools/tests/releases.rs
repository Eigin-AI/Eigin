//! Exercise just release dispatch without signing, cloud access or uploads.
use std::{fs, os::unix::fs::PermissionsExt, process::Command};
use tempfile::TempDir;

fn release(args: &[&str]) -> (std::process::Output, String) {
    let dir = TempDir::new().unwrap();
    fs::write(dir.path().join("justfile"), include_str!("../../justfile")).unwrap();
    let bin = dir.path().join("bin");
    fs::create_dir(&bin).unwrap();
    let cargo = bin.join("cargo");
    fs::write(
        &cargo,
        r#"#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$RELEASE_TEST_LOG"
case "$*" in
  *"config export ios") printf 'export DEVELOPMENT_TEAM=test-team\n' ;;
  *"config export tf-vars production") printf 'export WEBSITE_TEST_CONFIG=production\n' ;;
  *"website release") [ "${WEBSITE_TEST_CONFIG:-}" = production ] ;;
esac
"#,
    )
    .unwrap();
    fs::set_permissions(&cargo, fs::Permissions::from_mode(0o755)).unwrap();
    let log = dir.path().join("commands.log");
    let output = Command::new("just")
        .current_dir(dir.path())
        .arg("release")
        .args(args)
        .env(
            "PATH",
            format!("{}:{}", bin.display(), std::env::var("PATH").unwrap()),
        )
        .env("RELEASE_TEST_LOG", &log)
        .output()
        .expect("just must be installed for release dispatch tests");
    (output, fs::read_to_string(log).unwrap_or_default())
}

#[test]
fn website_release_bypasses_ios_generation_and_signing() {
    for args in [vec!["website"], vec!["website", "production"]] {
        let (output, log) = release(&args);
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(log.contains("config export tf-vars production"));
        assert!(log.contains("website release"));
        assert!(!log.contains("generate"));
        assert!(!log.contains("config export ios"));
        assert!(!log.contains("fastlane"));
    }
}

#[test]
fn website_release_rejects_staging_and_ios_tracks_before_any_commands() {
    for args in [
        vec!["website", "staging"],
        vec!["website", "production", "beta"],
    ] {
        let (output, log) = release(&args);
        assert!(!output.status.success());
        assert!(log.is_empty());
    }
}

#[test]
fn ios_release_keeps_staging_beta_defaults_and_explicit_tracks() {
    for (args, environment, lane) in [
        (vec![], "staging", "beta"),
        (
            vec!["ios", "production", "metadata"],
            "production",
            "sync_metadata",
        ),
    ] {
        let (output, log) = release(&args);
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(log.contains("generate all"));
        assert!(log.contains("config export ios"));
        assert!(log.contains(&format!("sh {lane} {environment}")));
        assert!(!log.contains("website release"));
    }
}
