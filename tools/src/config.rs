use anyhow::{Context, Result};
use serde::Deserialize;
use std::collections::HashMap;
use std::fs;
use std::process::Command;

#[derive(Deserialize)]
pub struct Config {
    pub platforms: HashMap<String, PlatformConfig>,
}

#[derive(Deserialize)]
pub struct PlatformConfig {
    pub localize: Option<LocalizeConfig>,
}

#[derive(Deserialize, Clone)]
pub struct LocalizeConfig {
    pub source: String,
    pub output: String,
    pub formatter: Option<String>,
    #[serde(rename = "validate-sources")]
    pub validate_sources: Option<String>,
}

pub fn load(repo_root: &str) -> Result<Config> {
    let path = format!("{repo_root}/tools.toml");
    let content = fs::read_to_string(&path).with_context(|| format!("reading {path}"))?;
    toml::from_str(&content).context("parsing tools.toml")
}

pub fn repo_root() -> Result<String> {
    let out = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .context("running git rev-parse --show-toplevel")?;
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}
