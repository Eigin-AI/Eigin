use anyhow::{Result, bail};
use std::{fs, path::Path, process::Command};

#[path = "support/version.rs"]
mod support;
use support::{APP_TOML, IOS, NPM, fixture, put};

#[test]
fn version_check_is_read_only_and_sync_is_idempotent() {
    let dir = fixture();
    let root = dir.path();
    version(root, "check").unwrap();
    let before = snapshots(root);
    version(root, "check").unwrap();
    assert_eq!(before, snapshots(root));
    version(root, "sync").unwrap();
    version(root, "sync").unwrap();
    assert_eq!(before, snapshots(root));
}

#[test]
fn version_product_bump_refreshes_locks_and_preserves_sdk_and_build_numbers() {
    let dir = fixture();
    let root = dir.path();
    set_versions(dir.path(), "1.2.0", "0.1.0");
    assert!(
        version(root, "check")
            .unwrap_err()
            .to_string()
            .contains("src/eigin_cli/Cargo.toml")
    );
    version(root, "sync").unwrap();
    version(root, "check").unwrap();
    let ios = fs::read_to_string(root.join(IOS)).unwrap();
    assert_eq!(ios.matches("1.2.0").count(), 2);
    assert!(ios.contains("CURRENT_PROJECT_VERSION: \"17\""));
    assert!(
        fs::read_to_string(root.join("src/eigin_cli/Cargo.toml"))
            .unwrap()
            .contains("# preserve")
    );
    assert!(
        fs::read_to_string(root.join(NPM))
            .unwrap()
            .contains("0.1.0")
    );
}

#[test]
fn version_rejects_invalid_authority_and_missing_fields() {
    let dir = fixture();
    for stream in ["product", "sdk"] {
        for value in ["01.0.0", "1.0", "1.0.0-beta.1", "1.0.0+build"] {
            let mut fixture: toml::Value = toml::from_str(APP_TOML).unwrap();
            fixture["version"][stream] = value.into();
            put(
                dir.path(),
                "config/app.toml",
                &toml::to_string(&fixture).unwrap(),
            );
            let error = version(dir.path(), "show").unwrap_err().to_string();
            assert!(error.contains("MAJOR.MINOR.PATCH"), "{error}");
        }
    }
    put(
        dir.path(),
        "config/app.toml",
        "[identity]\nbundle_id = \"test\"",
    );
    assert!(version(dir.path(), "show").is_err());
    put(dir.path(), "config/app.toml", APP_TOML);
    put(dir.path(), NPM, "{}");
    assert!(
        version(dir.path(), "check")
            .unwrap_err()
            .to_string()
            .contains(NPM)
    );
}

#[test]
fn version_sdk_drift_in_cli_and_npm_locks_is_detected() {
    let dir = fixture();
    set_versions(dir.path(), "1.0.0", "0.2.0");
    let drift = version(dir.path(), "check").unwrap_err().to_string();
    assert!(drift.contains("src/eigin_cli/Cargo.lock"));
    assert!(drift.contains("src/eigin_sdk/Cargo.lock"));
    assert!(drift.contains("package-lock.json"));
    assert!(drift.contains("eigin_sdk actual 0.1.0; expected 0.2.0"));
    assert!(drift.contains("@eigin/sdk actual 0.1.0; expected 0.2.0"));
    assert!(!drift.contains("src/eigin_relay/Cargo.lock"));
}

#[test]
fn version_failed_refresh_restores_manifests_and_locks() {
    let dir = fixture();
    let root = dir.path();
    let path = "src/eigin_relay/Cargo.toml";
    let before = fs::read_to_string(root.join(path)).unwrap()
        + "\n[dependencies]\nmissing-eigin-version-test-crate = { path = \"/nonexistent-eigin-test\" }\n";
    put(root, path, &before);
    set_versions(dir.path(), "1.1.0", "0.1.0");
    let before_files = snapshots(root);
    assert!(
        version(root, "sync")
            .unwrap_err()
            .to_string()
            .contains("restored")
    );
    assert_eq!(fs::read_to_string(root.join(path)).unwrap(), before);
    assert_eq!(snapshots(root), before_files);
}

#[test]
fn version_sdk_bump_refreshes_cargo_and_npm_without_changing_product() {
    let dir = fixture();
    let root = dir.path();
    fs::remove_file(root.join("package-lock.json")).unwrap();
    let output = std::process::Command::new("npm")
        .current_dir(root)
        .args([
            "install",
            "--package-lock-only",
            "--ignore-scripts",
            "--offline",
            "--no-audit",
            "--no-fund",
        ])
        .output()
        .expect("npm is required for SDK lock refresh tests");
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let product_before = fs::read_to_string(root.join(IOS)).unwrap();
    set_versions(dir.path(), "1.0.0", "0.2.0");
    version(root, "sync").unwrap();
    version(root, "check").unwrap();
    let locks = snapshots(root);
    version(root, "sync").unwrap();
    assert_eq!(locks, snapshots(root));
    assert_eq!(product_before, fs::read_to_string(root.join(IOS)).unwrap());
    assert!(
        fs::read_to_string(root.join("tools/Cargo.toml"))
            .unwrap()
            .contains("0.1.0")
    );
}

#[test]
fn version_checks_every_ios_scalar_style() {
    let dir = fixture();
    for scalar in ["'0.9.0'", "0.9.0", "\"0.9.0\""] {
        put(
            dir.path(),
            IOS,
            &format!("  MARKETING_VERSION: \"1.0.0\"\n  MARKETING_VERSION: {scalar} # companion\n"),
        );
        assert!(version(dir.path(), "check").is_err());
        version(dir.path(), "sync").unwrap();
        version(dir.path(), "check").unwrap();
        assert!(
            fs::read_to_string(dir.path().join(IOS))
                .unwrap()
                .contains("# companion")
        );
    }
    put(
        dir.path(),
        IOS,
        "  MARKETING_VERSION: \"1.0.0\"\n  MARKETING_VERSION: # missing\n",
    );
    assert!(version(dir.path(), "check").is_err());
}

fn version(root: &Path, action: &str) -> Result<String> {
    cli(root, &["version", action])
}

fn cli(root: &Path, args: &[&str]) -> Result<String> {
    let git_dir = Command::new("git")
        .args(["rev-parse", "--absolute-git-dir"])
        .current_dir(env!("CARGO_MANIFEST_DIR"))
        .output()
        .unwrap();
    assert!(git_dir.status.success());
    let output = Command::new(env!("CARGO_BIN_EXE_eigin-tools"))
        .current_dir(root)
        .args(args)
        .env("GIT_DIR", String::from_utf8(git_dir.stdout).unwrap().trim())
        .env("GIT_WORK_TREE", root)
        .output()?;
    if !output.status.success() {
        bail!("{}", String::from_utf8_lossy(&output.stderr));
    }
    Ok(String::from_utf8(output.stdout)?)
}

fn set_versions(root: &Path, product: &str, sdk: &str) {
    let mut config: toml::Value = toml::from_str(APP_TOML).unwrap();
    config["version"]["product"] = product.into();
    config["version"]["sdk"] = sdk.into();
    put(root, "config/app.toml", &toml::to_string(&config).unwrap());
}

fn snapshots(root: &Path) -> Vec<(String, Vec<u8>)> {
    let mut files: Vec<_> = walkdir::WalkDir::new(root)
        .into_iter()
        .map(Result::unwrap)
        .filter(|entry| entry.file_type().is_file())
        .map(|entry| {
            (
                entry
                    .path()
                    .strip_prefix(root)
                    .unwrap()
                    .to_string_lossy()
                    .into_owned(),
                fs::read(entry.path()).unwrap(),
            )
        })
        .collect();
    files.sort();
    files
}

#[test]
fn version_show_reports_both_release_identities() {
    let dir = fixture();
    set_versions(dir.path(), "2.3.4", "0.9.1");
    let output = version(dir.path(), "show").unwrap();
    assert!(output.contains("Product 2.3.4"));
    assert!(output.contains("SDK 0.9.1"));
}

#[test]
fn version_reports_paths_for_missing_and_malformed_managed_files() {
    let dir = fixture();
    for path in [
        "config/app.toml",
        "src/eigin_cli/Cargo.toml",
        NPM,
        IOS,
        "src/eigin_cli/Cargo.lock",
        "package-lock.json",
    ] {
        let original = fs::read(dir.path().join(path)).unwrap();
        fs::remove_file(dir.path().join(path)).unwrap();
        let error = version(dir.path(), "check").unwrap_err().to_string();
        assert!(error.contains(path), "{error}");
        put(dir.path(), path, "invalid!!!");
        let error = version(dir.path(), "check").unwrap_err().to_string();
        assert!(error.contains(path), "{error}");
        fs::write(dir.path().join(path), original).unwrap();
    }
}

#[test]
fn generation_synchronizes_versions_before_sdk_artifacts() {
    use std::os::unix::fs::PermissionsExt;
    let dir = fixture();
    let root = dir.path();
    put(root, "LICENSE", "SDK license text");
    set_versions(root, "1.2.0", "0.1.0");
    for tool in ["ubrn", "vite"] {
        let path = format!("node_modules/.bin/{tool}");
        put(
            root,
            &path,
            "#!/bin/sh\nmkdir -p ../target/web-bindings\nprintf generated > ../target/web-bindings/test.ts\n",
        );
        fs::set_permissions(root.join(path), fs::Permissions::from_mode(0o755)).unwrap();
    }
    cli(root, &["generate", "sdk", "web"]).unwrap();
    version(root, "check").unwrap();
    let catalog: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(root.join("src/eigin_sdk/NOTICES.json")).unwrap())
            .unwrap();
    assert_eq!(catalog["sdk"]["version"], "0.1.0");
    assert!(
        root.join("src/eigin_sdk/web/src/generated/test.ts")
            .exists()
    );
}

#[test]
fn generation_validates_versions_before_app_or_sdk_work() {
    let dir = fixture();
    put(dir.path(), "config/app.toml", "invalid!!!");
    for args in [
        vec!["generate"],
        vec!["generate", "ios"],
        vec!["generate", "web"],
        vec!["generate", "sdk", "web"],
    ] {
        let error = cli(dir.path(), &args).unwrap_err().to_string();
        assert!(error.contains("Parsing config/app.toml"), "{error}");
    }
    let before = snapshots(dir.path());
    let error = cli(dir.path(), &["generate", "docs"])
        .unwrap_err()
        .to_string();
    assert!(!error.contains("config/app.toml"), "{error}");
    assert_eq!(before, snapshots(dir.path()));
}
