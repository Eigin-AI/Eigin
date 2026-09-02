pub mod format_params;
pub mod generator;
pub mod identifiers;
pub mod parser;
pub mod scope_tree;
pub mod validator;

use anyhow::{Context, Result};
use std::fs;
use std::process::Command;

use crate::config::LocalizeConfig;

pub fn validate(repo_root: &str, config: &LocalizeConfig) -> Result<bool> {
    let sources = config
        .validate_sources
        .as_deref()
        .context("no validate-sources configured for ios in config/tools.toml")?;
    let sources_dir = format!("{repo_root}/{sources}");
    let output = format!("{repo_root}/{}", config.output);
    validator::validate(&sources_dir, &output)
}

pub fn generate(repo_root: &str, config: &LocalizeConfig) -> Result<()> {
    let source = format!("{repo_root}/{}", config.source);
    let output_path = format!("{repo_root}/{}", config.output);

    let entries = parser::parse(&source)?;
    let swift_code = generator::emit(&entries);

    fs::write(&output_path, &swift_code).with_context(|| format!("writing {output_path}"))?;

    if let Some(formatter) = &config.formatter {
        let status = Command::new(formatter)
            .arg(&output_path)
            .status()
            .with_context(|| format!("running {formatter}"))?;
        if !status.success() {
            anyhow::bail!("{formatter} failed on {output_path}");
        }
    }

    println!("Generated {output_path}");
    Ok(())
}
