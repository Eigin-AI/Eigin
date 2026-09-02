use anyhow::{Result, bail};

use crate::config;

/// Validate that all String(localized:) keys in source files exist in the generated output.
///
/// Reads platform configuration from config/tools.toml.
#[derive(clap::Args)]
pub struct ValidateArgs {
    /// Platform to validate (e.g. ios). Omit to validate all configured platforms.
    pub platform: Option<String>,
}

pub fn run(args: ValidateArgs) -> Result<()> {
    let root = config::repo_root()?;
    let passed = run_with_root(args, &root)?;
    if !passed {
        bail!("localization validation failed");
    }
    Ok(())
}

pub fn run_with_root(args: ValidateArgs, root: &str) -> Result<bool> {
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
        return Ok(true);
    }

    let mut all_passed = true;
    for (name, platform) in platforms {
        let Some(localize_config) = &platform.localize else {
            continue;
        };
        let passed = match name.as_str() {
            "ios" => super::ios::validate(root, localize_config)?,
            other => {
                eprintln!("warning: no validator for platform '{other}', skipping");
                true
            }
        };
        if !passed {
            all_passed = false;
        }
    }

    Ok(all_passed)
}
