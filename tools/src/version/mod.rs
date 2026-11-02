//! Explicit product and SDK release metadata management.
use anyhow::{Context, Result, bail, ensure};
use regex::Regex;
use std::{fs, path::Path};

use crate::config::model::Versions;
mod locks;

const CARGO_TARGETS: &[(&str, bool)] = &[
    ("src/eigin_relay/Cargo.toml", false),
    ("src/eigin_cli/Cargo.toml", false),
    ("src/eigin_sdk/crates/eigin_sdk/Cargo.toml", true),
];
const IOS: &str = "src/eigin_ios/project.yml";
const NPM: &str = "src/eigin_sdk/web/package.json";

/// Inspect or synchronize committed release metadata.
#[derive(clap::Args)]
pub struct Args {
    #[command(subcommand)]
    command: VersionCommand,
}

#[derive(clap::Subcommand)]
enum VersionCommand {
    /// Print the product and SDK release identity.
    Show,
    /// Update managed manifests and refresh lock metadata.
    Sync,
    /// Reject drift without modifying files or accessing the network.
    Check,
}

/// Run without environment secrets or deployment configuration.
pub fn run(args: Args) -> Result<()> {
    let root = crate::config::repo_root()?;
    let root = Path::new(&root);
    let versions = load_versions(root)?;
    match args.command {
        VersionCommand::Show => {
            println!("Product {}\nSDK {}", versions.product, versions.sdk);
            Ok(())
        }
        VersionCommand::Check => check(root, &versions),
        VersionCommand::Sync => sync(root, &versions),
    }
}

fn load_versions(root: &Path) -> Result<Versions> {
    let config: crate::config::model::AppConfig =
        toml::from_str(&read(root, "config/app.toml")?).context("Parsing config/app.toml")?;
    for value in [&config.version.product, &config.version.sdk] {
        let version = semver::Version::parse(value).context("Expected MAJOR.MINOR.PATCH")?;
        ensure!(
            version.pre.is_empty() && version.build.is_empty(),
            "Release versions must be MAJOR.MINOR.PATCH: {value}"
        );
    }
    Ok(config.version)
}

struct Change {
    path: String,
    before: String,
    after: String,
}

fn manifests(root: &Path, versions: &Versions) -> Result<Vec<Change>> {
    let mut changes = Vec::new();
    for &(path, sdk) in CARGO_TARGETS {
        let before = read(root, path)?;
        let mut doc = before
            .parse::<toml_edit::DocumentMut>()
            .with_context(|| format!("Parsing {path}"))?;
        let expected = if sdk {
            &versions.sdk
        } else {
            &versions.product
        };
        let value = doc["package"]["version"]
            .as_value_mut()
            .context(format!("Missing package.version in {path}"))?;
        ensure!(
            value.as_str().is_some(),
            "Expected string package.version in {path}"
        );
        let decor = value.decor().clone();
        *value = toml_edit::Value::from(expected.as_str());
        *value.decor_mut() = decor;
        changes.push(Change {
            path: path.into(),
            before,
            after: doc.to_string(),
        });
    }
    let before = read(root, NPM)?;
    let mut json: serde_json::Value =
        serde_json::from_str(&before).with_context(|| format!("Parsing {NPM}"))?;
    ensure!(json["version"].is_string(), "Missing version in {NPM}");
    // Replace only the top-level version line; parsing above validates the document.
    let pattern = Regex::new(r#"(?m)^(  "version": )"[^"]*""#)?;
    ensure!(
        pattern.find_iter(&before).count() == 1,
        "Expected one top-level version line in {NPM}"
    );
    json["version"] = versions.sdk.clone().into();
    let after = pattern
        .replace(&before, |caps: &regex::Captures| {
            format!("{}\"{}\"", &caps[1], versions.sdk)
        })
        .into_owned();
    ensure!(
        serde_json::from_str::<serde_json::Value>(&after)? == json,
        "Unexpected npm manifest edit"
    );
    changes.push(Change {
        path: NPM.into(),
        before,
        after,
    });
    let before = read(root, IOS)?;
    let declarations = Regex::new(r"(?m)^[ \t]*MARKETING_VERSION:")?;
    let pattern = Regex::new(
        r#"(?m)^([ \t]*MARKETING_VERSION:[ \t]*)("[^"\r\n]*"|'[^'\r\n]*'|[^ \t#\r\n]+)([ \t]*(?:#[^\r\n]*)?)$"#,
    )?;
    let count = declarations.find_iter(&before).count();
    ensure!(count > 0, "Missing MARKETING_VERSION in {IOS}");
    ensure!(
        pattern.find_iter(&before).count() == count,
        "Unsupported MARKETING_VERSION syntax in {IOS}; use a scalar release version"
    );
    let after = pattern
        .replace_all(&before, |caps: &regex::Captures| {
            let raw = &caps[2];
            let quote = if raw.starts_with('\"') {
                "\""
            } else if raw.starts_with('\'') {
                "'"
            } else {
                ""
            };
            format!("{}{quote}{}{quote}{}", &caps[1], versions.product, &caps[3])
        })
        .into_owned();
    changes.push(Change {
        path: IOS.into(),
        before,
        after,
    });
    Ok(changes)
}

fn check(root: &Path, versions: &Versions) -> Result<()> {
    let mut drift = Vec::new();
    for change in manifests(root, versions)? {
        if change.before != change.after {
            for (actual, expected) in change.before.lines().zip(change.after.lines()) {
                if actual != expected {
                    drift.push(format!(
                        "{}: actual `{}`; expected `{}` (run just version sync)",
                        change.path,
                        actual.trim(),
                        expected.trim()
                    ));
                }
            }
        }
    }
    drift.extend(locks::inspect(root, versions)?);
    if !drift.is_empty() {
        bail!("Version drift:\n{}", drift.join("\n"));
    }
    Ok(())
}

fn sync(root: &Path, versions: &Versions) -> Result<()> {
    let changes = manifests(root, versions)?;
    let locks = locks::snapshots(root)?;
    // Validate the complete input before any writes.
    locks::inspect(root, versions)?;
    let result = (|| {
        for change in &changes {
            if change.before != change.after {
                fs::write(root.join(&change.path), &change.after)?;
            }
        }
        locks::refresh(root, versions, &locks)?;
        check(root, versions)
    })();
    if let Err(error) = result {
        for change in &changes {
            fs::write(root.join(&change.path), &change.before)?;
        }
        for (path, content) in &locks {
            fs::write(root.join(path), content)?;
        }
        bail!(
            "Version sync failed; managed manifests and locks restored. Fix the reported error and rerun just version sync: {error:#}"
        );
    }
    Ok(())
}

fn read(root: &Path, path: &str) -> Result<String> {
    fs::read_to_string(root.join(path)).with_context(|| format!("Reading {path}"))
}

/// Synchronize release metadata before generating consumer artifacts.
pub fn generate(root: &Path) -> Result<()> {
    sync(root, &load_versions(root)?)
}
