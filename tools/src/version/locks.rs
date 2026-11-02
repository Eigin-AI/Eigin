//! Validate local package records without resolving dependencies during checks.
use super::*;
use std::process::Command;

const CARGO_LOCKS: &[(&str, &str, &[&str])] = &[
    (
        "src/eigin_relay/Cargo.lock",
        "src/eigin_relay/Cargo.toml",
        &["eigin-relay"],
    ),
    (
        "src/eigin_cli/Cargo.lock",
        "src/eigin_cli/Cargo.toml",
        &["eigin-cli", "eigin_sdk"],
    ),
    (
        "src/eigin_sdk/Cargo.lock",
        "src/eigin_sdk/Cargo.toml",
        &["eigin_sdk"],
    ),
    ("tools/Cargo.lock", "tools/Cargo.toml", &[]),
];
const NPM_LOCK: &str = "package-lock.json";

pub(super) fn snapshots(root: &Path) -> Result<Vec<(String, String)>> {
    CARGO_LOCKS
        .iter()
        .map(|&(path, _, _)| path)
        .chain([NPM_LOCK])
        .map(|path| Ok((path.into(), read(root, path)?)))
        .collect()
}

fn expected<'a>(name: &str, versions: &'a Versions) -> &'a str {
    if name == "eigin_sdk" {
        &versions.sdk
    } else {
        &versions.product
    }
}

fn cargo_expected(text: &str, names: &[&str], versions: &Versions) -> Result<toml::Value> {
    let mut doc: toml::Value = toml::from_str(text)?;
    let packages = doc
        .get_mut("package")
        .and_then(toml::Value::as_array_mut)
        .context("Missing lock packages")?;
    for name in names {
        let matches: Vec<_> = packages
            .iter_mut()
            .filter(|p| {
                p.get("name").and_then(toml::Value::as_str) == Some(name)
                    && p.get("source").is_none()
            })
            .collect();
        ensure!(
            matches.len() == 1,
            "Expected one local lock record for {name}"
        );
        for package in matches {
            ensure!(
                package
                    .get("version")
                    .and_then(toml::Value::as_str)
                    .is_some(),
                "Missing lock version for {name}"
            );
            package["version"] = expected(name, versions).into();
        }
    }
    Ok(doc)
}

fn npm_expected(text: &str, versions: &Versions) -> Result<serde_json::Value> {
    let mut doc: serde_json::Value = serde_json::from_str(text)?;
    let package = doc
        .pointer_mut("/packages/src~1eigin_sdk~1web")
        .context("Missing SDK npm workspace lock record")?;
    ensure!(
        package["version"].is_string(),
        "Missing SDK npm lock version"
    );
    package["version"] = versions.sdk.clone().into();
    Ok(doc)
}

pub(super) fn inspect(root: &Path, versions: &Versions) -> Result<Vec<String>> {
    let mut drift = Vec::new();
    for &(path, _, names) in CARGO_LOCKS {
        let text = read(root, path)?;
        let actual: toml::Value =
            toml::from_str(&text).with_context(|| format!("Parsing {path}"))?;
        cargo_expected(&text, names, versions).with_context(|| path)?;
        for package in actual["package"].as_array().unwrap() {
            let name = package
                .get("name")
                .and_then(toml::Value::as_str)
                .unwrap_or_default();
            if names.contains(&name) && package.get("source").is_none() {
                let actual = package["version"].as_str().unwrap();
                let expected = expected(name, versions);
                if actual != expected {
                    drift.push(format!(
                        "{path}: {name} actual {actual}; expected {expected}"
                    ));
                }
            }
        }
    }
    let text = read(root, NPM_LOCK)?;
    let actual: serde_json::Value =
        serde_json::from_str(&text).with_context(|| format!("Parsing {NPM_LOCK}"))?;
    npm_expected(&text, versions).with_context(|| NPM_LOCK)?;
    let actual = actual["packages"]["src/eigin_sdk/web"]["version"]
        .as_str()
        .unwrap();
    if actual != versions.sdk {
        drift.push(format!(
            "{NPM_LOCK}: @eigin/sdk actual {actual}; expected {}",
            versions.sdk
        ));
    }
    Ok(drift)
}

pub(super) fn refresh(
    root: &Path,
    versions: &Versions,
    snapshots: &[(String, String)],
) -> Result<()> {
    for &(path, manifest, names) in CARGO_LOCKS {
        let before = &snapshots.iter().find(|(p, _)| p == path).unwrap().1;
        let expected = cargo_expected(before, names, versions).with_context(|| path)?;
        if toml::from_str::<toml::Value>(before)? == expected {
            continue;
        }
        let output = Command::new("cargo")
            .current_dir(root)
            .args([
                "update",
                "--workspace",
                "--offline",
                "--manifest-path",
                manifest,
            ])
            .output()?;
        ensure!(
            output.status.success(),
            "Cargo lock refresh failed for {path}: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        let actual: toml::Value =
            toml::from_str(&read(root, path)?).with_context(|| format!("Parsing {path}"))?;
        ensure!(
            actual == expected,
            "Refusing unrelated dependency changes in {path}"
        );
    }
    let before = &snapshots.iter().find(|(p, _)| p == NPM_LOCK).unwrap().1;
    let expected = npm_expected(before, versions).with_context(|| NPM_LOCK)?;
    if serde_json::from_str::<serde_json::Value>(before)? != expected {
        let output = Command::new("npm")
            .current_dir(root)
            .args([
                "install",
                "--package-lock-only",
                "--ignore-scripts",
                "--offline",
                "--no-audit",
                "--no-fund",
            ])
            .output()?;
        ensure!(
            output.status.success(),
            "npm lock refresh failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        let actual: serde_json::Value = serde_json::from_str(&read(root, NPM_LOCK)?)
            .with_context(|| format!("Parsing {NPM_LOCK}"))?;
        ensure!(
            actual == expected,
            "Refusing unrelated dependency changes in {NPM_LOCK}"
        );
    }
    Ok(())
}
