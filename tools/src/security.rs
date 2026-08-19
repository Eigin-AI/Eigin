use anyhow::{Context, Result};
use serde_json::Value;
use std::fs;
use std::process::Command;

use crate::config;

/// Scan dependencies and the Relay image for known vulnerabilities.
///
/// - Deps: cargo-audit against the relay and tools lockfiles.
/// - Image: trivy against a locally built relay image.
/// - Config: trivy against the Dockerfile and Terraform.
///
/// Full JSON reports land in logs/security/ with every severity and its CVSS
/// scores; the console shows only what needs acting on.
#[derive(clap::Args)]
pub struct SecurityArgs {
    /// What to scan.
    #[arg(value_enum, default_value_t = Scope::All)]
    scope: Scope,
}

#[derive(Clone, Copy, PartialEq, clap::ValueEnum)]
pub enum Scope {
    All,
    Deps,
    Image,
    Config,
}

pub fn run(args: SecurityArgs) -> Result<()> {
    let root = config::repo_root()?;
    let reports = format!("{root}/logs/security");
    fs::create_dir_all(&reports).with_context(|| format!("creating {reports}"))?;

    let mut found = false;

    if matches!(args.scope, Scope::All | Scope::Deps) {
        found |= scan_deps(&root, &reports)?;
    }
    if matches!(args.scope, Scope::All | Scope::Image) {
        found |= scan_image(&root, &reports)?;
    }
    if matches!(args.scope, Scope::All | Scope::Config) {
        found |= scan_config(&root, &reports)?;
    }

    println!("\nReports written to logs/security");
    if found {
        anyhow::bail!("vulnerabilities found");
    }
    Ok(())
}

/// Crates to audit, and whether they ship. Only shipped code fails the run:
/// findings in build tooling are worth seeing but are not part of the product.
const AUDITED: &[(&str, bool)] = &[("src/eigin_relay", true), ("tools", false)];

fn scan_deps(root: &str, reports: &str) -> Result<bool> {
    require("cargo-audit", "cargo install cargo-audit --locked")?;

    let mut found = false;
    for (crate_dir, ships) in AUDITED {
        let name = crate_dir.rsplit('/').next().unwrap();
        let label = if *ships { "" } else { ", not shipped" };
        println!("==> cargo audit ({name}{label})");

        let out = Command::new("cargo")
            .args(["audit", "--json"])
            .current_dir(format!("{root}/{crate_dir}"))
            .output()
            .context("running cargo audit")?;

        let report = format!("{reports}/cargo-audit-{name}.json");
        fs::write(&report, &out.stdout).with_context(|| format!("writing {report}"))?;

        found |= report_advisories(&out.stdout) && *ships;
    }
    Ok(found)
}

/// Prints each vulnerability from a cargo-audit report. Warnings (unmaintained,
/// unsound, yanked) stay in the JSON only: they are advisories, not vulnerabilities.
fn report_advisories(stdout: &[u8]) -> bool {
    let Ok(json) = serde_json::from_slice::<Value>(stdout) else {
        println!("  could not parse report");
        return false;
    };
    let list = json["vulnerabilities"]["list"].as_array().cloned();
    let Some(list) = list.filter(|l| !l.is_empty()) else {
        println!("  no vulnerabilities");
        return false;
    };

    for v in &list {
        let advisory = &v["advisory"];
        let package = &v["package"];
        let fix = v["versions"]["patched"]
            .as_array()
            .filter(|p| !p.is_empty())
            .map(|p| {
                p.iter()
                    .filter_map(|s| s.as_str())
                    .collect::<Vec<_>>()
                    .join(", ")
            })
            .unwrap_or_else(|| "no fix available".into());

        println!(
            "  {} {}: {}",
            package["name"].as_str().unwrap_or("?"),
            package["version"].as_str().unwrap_or("?"),
            advisory["id"].as_str().unwrap_or("?"),
        );
        println!("    {}", advisory["title"].as_str().unwrap_or(""));
        println!("    fix: {fix}");
    }
    true
}

fn scan_image(root: &str, reports: &str) -> Result<bool> {
    require("trivy", "brew install trivy")?;
    require("docker", "brew install --cask docker")?;

    println!("==> building eigin-relay:scan");
    // Pinned to the deployed platform: the Dockerfile cross-compiles to
    // x86_64-musl, and scanning any other architecture would describe an
    // artifact we never ship. Emulated on arm64 hosts, so expect it to be slow.
    let built = Command::new("docker")
        .args([
            "build",
            "--platform",
            "linux/amd64",
            "-q",
            "-t",
            "eigin-relay:scan",
            ".",
        ])
        .current_dir(format!("{root}/src/eigin_relay"))
        .status()
        .context("running docker build")?;
    if !built.success() {
        anyhow::bail!("docker build failed");
    }

    // Export to a tarball rather than scanning the daemon's copy: Docker's
    // containerd snapshotter does not expose a cross-platform image's layers to
    // other clients, so trivy cannot read it in place.
    let tarball = std::env::temp_dir().join("eigin-relay-scan.tar");
    let saved = Command::new("docker")
        .arg("save")
        .arg("-o")
        .arg(&tarball)
        .arg("eigin-relay:scan")
        .status()
        .context("running docker save")?;
    if !saved.success() {
        anyhow::bail!("docker save failed");
    }

    println!("==> trivy image");
    let report = format!("{reports}/trivy-relay.json");
    let status = Command::new("trivy")
        .args(["image", "--scanners", "vuln", "--format", "json", "-o"])
        .arg(&report)
        .arg("--input")
        .arg(&tarball)
        .status()
        .context("running trivy")?;
    let _ = fs::remove_file(&tarball);
    if !status.success() {
        anyhow::bail!("trivy failed");
    }

    let json: Value = serde_json::from_str(
        &fs::read_to_string(&report).with_context(|| format!("reading {report}"))?,
    )
    .context("parsing trivy report")?;
    Ok(report_image_vulnerabilities(&json))
}

/// Prints image vulnerabilities rated High or Critical.
fn report_image_vulnerabilities(json: &Value) -> bool {
    let mut found = false;
    for result in json["Results"].as_array().unwrap_or(&vec![]) {
        for vuln in result["Vulnerabilities"].as_array().unwrap_or(&vec![]) {
            let severity = vuln["Severity"].as_str().unwrap_or("");
            if !matches!(severity, "HIGH" | "CRITICAL") {
                continue;
            }
            found = true;
            println!(
                "  {} {}: {} ({severity})",
                vuln["PkgName"].as_str().unwrap_or("?"),
                vuln["InstalledVersion"].as_str().unwrap_or("?"),
                vuln["VulnerabilityID"].as_str().unwrap_or("?"),
            );
            println!(
                "    fix: {}",
                vuln["FixedVersion"].as_str().unwrap_or("no fix available"),
            );
        }
    }
    if !found {
        println!("  no high or critical vulnerabilities");
    }
    found
}

/// Scans the Dockerfile and Terraform for insecure configuration.
fn scan_config(root: &str, reports: &str) -> Result<bool> {
    require("trivy", "brew install trivy")?;

    let mut found = false;
    for (dir, name) in [
        ("src/eigin_relay", "dockerfile"),
        ("infra/scaleway", "terraform"),
    ] {
        println!("==> trivy config ({name})");

        let report = format!("{reports}/trivy-config-{name}.json");
        let status = Command::new("trivy")
            .args(["config", "--quiet", "--format", "json", "-o"])
            .arg(&report)
            .arg(format!("{root}/{dir}"))
            .status()
            .context("running trivy config")?;
        if !status.success() {
            anyhow::bail!("trivy config failed for {dir}");
        }

        let json: Value = serde_json::from_str(
            &fs::read_to_string(&report).with_context(|| format!("reading {report}"))?,
        )
        .context("parsing trivy config report")?;
        found |= report_misconfigurations(&json);
    }
    Ok(found)
}

/// Prints misconfigurations rated High or Critical.
fn report_misconfigurations(json: &Value) -> bool {
    let mut found = false;
    for result in json["Results"].as_array().unwrap_or(&vec![]) {
        for item in result["Misconfigurations"].as_array().unwrap_or(&vec![]) {
            let severity = item["Severity"].as_str().unwrap_or("");
            if !matches!(severity, "HIGH" | "CRITICAL") {
                continue;
            }
            found = true;
            println!(
                "  {}: {} ({severity})",
                item["ID"].as_str().unwrap_or("?"),
                item["Title"].as_str().unwrap_or(""),
            );
        }
    }
    if !found {
        println!("  no high or critical misconfigurations");
    }
    found
}

/// Fails with an install hint when a scanner is missing.
fn require(tool: &str, install: &str) -> Result<()> {
    let found = Command::new("which")
        .arg(tool)
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false);
    if !found {
        anyhow::bail!("{tool} not found. Install with: {install}");
    }
    Ok(())
}
