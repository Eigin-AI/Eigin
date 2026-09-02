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
            "ios" => super::ios::generate(root, localize_config)?,
            other => eprintln!("warning: no generator for platform '{other}', skipping"),
        }
    }

    Ok(())
}
