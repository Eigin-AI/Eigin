use anyhow::{Result, bail};

use crate::config;

/// Generate localization source files from the catalog.
///
/// Reads platform configuration from config/tools.toml.
/// Each configured platform with a localize section will have its
/// source files generated and formatted.
#[derive(clap::Args)]
pub struct GenerateArgs {
    /// Platform to generate for (e.g. ios). Omit to generate all configured platforms.
    pub platform: Option<String>,
}

pub fn run(args: GenerateArgs) -> Result<()> {
    let root = config::repo_root()?;
    run_with_root(args, &root)
}

pub fn run_with_root(args: GenerateArgs, root: &str) -> Result<()> {
    let cfg = config::load(root)?.tools;

    let platforms: Vec<_> = cfg
        .platforms
        .iter()
        .filter(|(name, _)| {
            args.platform
                .as_deref()
                .map_or(true, |p| p == name.as_str())
        })
        .collect();

    if platforms.is_empty() {
        if let Some(p) = &args.platform {
            bail!("platform '{p}' not found in config/tools.toml");
        }
        return Ok(());
    }

    for (name, platform) in platforms {
        let Some(localize_config) = &platform.localize else {
            continue;
        };
        match name.as_str() {
            "ios" => {
                let skipped = super::ios::generate(root, localize_config)?;
                let allowlist = match &localize_config.allowlist {
                    Some(p) => super::allowlist::load(root, p)?,
                    None => super::allowlist::Allowlist::default(),
                };
                let actionable: Vec<_> = skipped
                    .iter()
                    .filter(|s| !allowlist.keys.contains(&s.key))
                    .cloned()
                    .collect();
                print_skipped_summary(&actionable, skipped.len(), &localize_config.allowlist);
            }
            other => eprintln!("warning: no generator for platform '{other}', skipping"),
        }
    }

    // Non-blocking coverage warning: a missed translation should be visible
    // on every generate without failing the build. Lint is the gate.
    super::check_all_report(root)?;

    Ok(())
}

/// Print a compact summary of keys the generator skipped because they are
/// not `domain.element` shaped.
///
/// These are strings Xcode auto-extracted (often from `Text("…")` literals
/// in previews) or copy that should have been a localization key. Allowlisted
/// keys (e.g. NSLocalizedString entries with int format params the generator
/// can't represent) are excluded before this is called. A short summary keeps
/// the signal where per-key `WARNING` lines taught the agent to ignore noise.
fn print_skipped_summary(
    actionable: &[super::ios::parser::SkippedKey],
    total_skipped: usize,
    allowlist_path_opt: &Option<String>,
) {
    if actionable.is_empty() {
        return;
    }
    let samples: Vec<&str> = actionable.iter().take(3).map(|s| s.key.as_str()).collect();
    let suppressed = total_skipped - actionable.len();
    let suppressed_note = if suppressed > 0 {
        format!(" ({suppressed} allowlisted)")
    } else {
        String::new()
    };
    eprintln!(
        "Skipped {} catalog entries without a localization-key structure{suppressed_note}. \
        These are Text(…) literals or preview strings Xcode auto-extracted. \
        Sample: {}.",
        actionable.len(),
        samples
            .iter()
            .map(|s| format!("'{s}'"))
            .collect::<Vec<_>>()
            .join(", ")
    );
    let allowlist = allowlist_path_opt
        .as_deref()
        .unwrap_or("<no allowlist configured>");
    eprintln!(
        "Migrate to a domain.element key, or add to the allowlist at {allowlist}\n(configured as `localize.allowlist` in config/tools.toml) if intentional."
    );
}
