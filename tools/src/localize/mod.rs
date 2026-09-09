pub mod allowlist;
pub mod coverage;
pub mod ios;

use anyhow::{Context, Result, bail};
use clap::Subcommand;

pub mod generate;
pub mod validate;

/// Localization codegen and validation.
///
/// Generates and validates platform-specific localization source files
/// from the shared Localizable.xcstrings catalog.
#[derive(clap::Args)]
pub struct Args {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Generate localization source files from catalog.
    Generate(generate::GenerateArgs),
    /// Validate that all String(localized:) keys exist in the generated output.
    Validate(validate::ValidateArgs),
    /// Check that every key with a localization is translated for each
    /// required language. Exits non-zero on offenders outside the allowlist.
    Check(CheckArgs),
}

#[derive(clap::Args)]
pub struct CheckArgs {
    /// Platform to check (e.g. ios). Omit to check all configured platforms.
    pub platform: Option<String>,
}

pub fn run(args: Args) -> Result<()> {
    match args.command {
        Command::Generate(args) => generate::run(args),
        Command::Validate(args) => validate::run(args),
        Command::Check(args) => run_check(args),
    }
}

fn run_check(args: CheckArgs) -> Result<()> {
    let root = crate::config::repo_root()?;
    let passed = check_all(&root, args.platform.as_deref())?;
    if !passed {
        bail!("localization coverage check failed");
    }
    Ok(())
}

/// Generate localization for all configured platforms. Called by `eigin-tools generate`.
pub fn generate_all(repo_root: &str) -> Result<()> {
    generate::run_with_root(generate::GenerateArgs { platform: None }, repo_root)
}

/// Validate localization for all configured platforms. Called by `eigin-tools lint`.
pub fn validate_all(repo_root: &str) -> Result<bool> {
    validate::run_with_root(validate::ValidateArgs { platform: None }, repo_root)
}

/// Run the coverage check for all configured platforms. Used by `localize check`.
/// Returns false when any required language is missing (outside the allowlist).
pub fn check_all(repo_root: &str, platform: Option<&str>) -> Result<bool> {
    check_coverage(repo_root, platform, CoverageMode::Strict)
}

/// Non-blocking coverage warning run from `eigin-tools generate`. Never fails
/// the build; prints a summary of offenders so the agent notices them.
pub fn check_all_report(repo_root: &str) -> Result<()> {
    check_coverage(repo_root, None, CoverageMode::Warn)?;
    Ok(())
}

enum CoverageMode {
    /// Fail on offenders (used by lint and `localize check`).
    Strict,
    /// Print a warning, never fail (used by generate).
    Warn,
}

fn check_coverage(repo_root: &str, platform: Option<&str>, mode: CoverageMode) -> Result<bool> {
    let cfg = crate::config::load(repo_root)?.tools;

    let platforms: Vec<_> = cfg
        .platforms
        .iter()
        .filter(|(name, _)| platform.map_or(true, |p| p == name.as_str()))
        .collect();

    if let Some(p) = platform {
        if platforms.is_empty() {
            bail!("platform '{p}' not found in config/tools.toml");
        }
    }

    let mut all_passed = true;
    for (name, platform_config) in platforms {
        let Some(localize_config) = &platform_config.localize else {
            continue;
        };

        let required = localize_config
            .required_languages
            .as_deref()
            .with_context(|| {
                format!("no required-languages configured for platform {name} in config/tools.toml")
            })?;

        // No required languages means the check is a no-op for this platform.
        if required.is_empty() {
            continue;
        }

        let catalog_path = format!("{repo_root}/{}", localize_config.source);
        let content = std::fs::read_to_string(&catalog_path)
            .with_context(|| format!("reading {catalog_path}"))?;
        let catalog: serde_json::Value =
            serde_json::from_str(&content).with_context(|| format!("parsing {catalog_path}"))?;

        let allowlist = match &localize_config.allowlist {
            Some(p) => allowlist::load(repo_root, p)?,
            None => allowlist::Allowlist::default(),
        };

        let report = coverage::check(&catalog, required, &allowlist);

        match mode {
            CoverageMode::Strict => {
                if !report.is_clean() {
                    eprintln!("Localization coverage check failed for {name}:");
                    print_detail(&report);
                    all_passed = false;
                } else if !report.allowlisted.is_empty() {
                    eprintln!(
                        "{name}: {} translation(s) allowlisted across {} keys.",
                        report.allowlisted.len(),
                        report.total_keys
                    );
                } else {
                    eprintln!(
                        "{name}: all {} keys translated for {}.",
                        report.total_keys,
                        required.join(", ")
                    );
                }
            }
            CoverageMode::Warn => {
                let allowlist_path = localize_config
                    .allowlist
                    .as_deref()
                    .unwrap_or("<no allowlist configured>");
                report.print_warn(allowlist_path);
            }
        }
    }

    Ok(all_passed)
}

fn print_detail(report: &coverage::CoverageReport) {
    for m in &report.missing {
        eprintln!(
            "  {} — missing {} ({})",
            m.key,
            m.lang,
            match m.reason {
                coverage::MissingReason::NoEntry => "no entry",
                coverage::MissingReason::NotTranslated => "not translated",
            }
        );
    }
}
