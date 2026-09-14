use anyhow::{Context, Result};
use std::collections::HashMap;
use std::fs;
use std::process::Command;

use super::model::{Config, Env};

/// Committed config plus the secrets it needs, resolved together.
///
/// Not scoped to an environment: `export ios` renders both at once, while
/// `export relay` and `export tf-vars` render one. Environment is a renderer
/// argument, not part of resolution.
pub struct Resolved {
    pub config: Config,
    pub secrets: Secrets,
}

/// The parsed `.env`. This is the only thing in the repo that reads it.
pub struct Secrets(HashMap<String, String>);

/// Prefixes used by the placeholders `config init` seeds. A value still carrying
/// one has not been filled in, so it counts as unset — otherwise copying the
/// template would satisfy every check while configuring nothing.
const PLACEHOLDER_PREFIXES: [&str; 2] = ["YOUR_", "TODO_"];

fn is_placeholder(value: &str) -> bool {
    PLACEHOLDER_PREFIXES
        .iter()
        .any(|prefix| value.starts_with(prefix))
}

impl Secrets {
    /// Parse a `.env` file. A missing file is an empty set, not an error — the
    /// per-value `require` calls produce the actionable message instead.
    pub fn load(path: &str) -> Self {
        Secrets(parse_dot_env(path))
    }

    /// A usable value, or `None` when unset, empty, or still a placeholder.
    pub fn get(&self, key: &str) -> Option<&str> {
        self.0
            .get(key)
            .map(String::as_str)
            .filter(|v| !v.is_empty() && !is_placeholder(v))
    }

    /// A usable value for the environment, or `None`.
    pub fn get_env(&self, key: &str, env: Env) -> Option<&str> {
        self.get(&format!("{key}_{}", env.suffix()))
    }

    #[cfg(test)]
    pub fn from_map(values: HashMap<String, String>) -> Self {
        Secrets(values)
    }

    /// A secret that must be present. Errors name the key so the fix is obvious.
    pub fn require(&self, key: &str) -> Result<&str> {
        self.get(key).with_context(|| format!("set {key} in .env"))
    }

    /// A required secret, suffixed with the environment.
    pub fn require_env(&self, key: &str, env: Env) -> Result<&str> {
        self.require(&format!("{key}_{}", env.suffix()))
    }

    /// A secret that is allowed to be unset (rotation keys, release-only creds).
    pub fn optional(&self, key: &str) -> &str {
        self.get(key).unwrap_or("")
    }

    /// An optional secret, suffixed with the environment.
    pub fn optional_env(&self, key: &str, env: Env) -> &str {
        self.optional(&format!("{key}_{}", env.suffix()))
    }

    /// Every `<prefix><NAME><suffix>` entry that is still a placeholder, by key.
    ///
    /// These are dropped from `matching`, so callers surface them rather than
    /// shipping a quietly partial set.
    pub fn placeholders_matching(&self, prefix: &str, suffix: &str) -> Vec<String> {
        let mut found: Vec<String> = self
            .0
            .iter()
            .filter(|(key, value)| {
                key.starts_with(prefix) && key.ends_with(suffix) && is_placeholder(value)
            })
            .map(|(key, _)| key.clone())
            .collect();
        found.sort();
        found
    }

    /// Every usable `<prefix><NAME><suffix>` entry, as `(NAME, value)` pairs.
    pub fn matching(&self, prefix: &str, suffix: &str) -> Vec<(String, String)> {
        let mut found: Vec<(String, String)> = self
            .0
            .iter()
            .filter_map(|(key, value)| {
                let name = key.strip_prefix(prefix)?.strip_suffix(suffix)?;
                let usable = !value.is_empty() && !is_placeholder(value);
                (!name.is_empty() && usable).then(|| (name.to_string(), value.clone()))
            })
            .collect();
        found.sort();
        found
    }
}

/// Load everything under `config/` and the secrets alongside it.
pub fn resolve(repo_root: &str) -> Result<Resolved> {
    Ok(Resolved {
        config: super::load(repo_root)?,
        secrets: Secrets::load(&format!("{repo_root}/.env")),
    })
}

/// Values read from the environment rather than configured: Scaleway CLI
/// credentials and the current commit. Only the Terraform renderer needs these,
/// so they are loaded on demand rather than during `resolve`.
pub struct Derived {
    pub scw_secret_key: String,
    pub scw_access_key: String,
    pub scw_region: String,
    pub image_tag: String,
}

impl Derived {
    pub fn load() -> Self {
        Derived {
            scw_secret_key: scw_config_get("secret-key").unwrap_or_default(),
            scw_access_key: scw_config_get("access-key").unwrap_or_default(),
            scw_region: scw_config_get("default-region").unwrap_or_default(),
            image_tag: git_short_head().unwrap_or_default(),
        }
    }
}

/// Parse a `.env` file into a map. Silently returns an empty map if the file doesn't exist.
pub fn parse_dot_env(path: &str) -> HashMap<String, String> {
    let Ok(content) = fs::read_to_string(path) else {
        return HashMap::new();
    };
    content
        .lines()
        .filter_map(|line| {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                return None;
            }
            let line = line.strip_prefix("export ").unwrap_or(line);
            let (key, value) = line.split_once('=')?;
            let value = value.trim_matches('"').trim_matches('\'').to_string();
            Some((key.to_string(), value))
        })
        .collect()
}

/// Read an environment's non-secret tfvars into a map.
///
/// Terraform remains the source of truth for infra config; this parses it so the
/// relay renderer doesn't have to duplicate those values.
pub fn tfvars(repo_root: &str, env: Env) -> Result<HashMap<String, String>> {
    let path = format!(
        "{repo_root}/infra/scaleway/environments/{}.tfvars",
        env.as_str()
    );
    let content = fs::read_to_string(&path).with_context(|| format!("reading {path}"))?;
    Ok(content
        .lines()
        .filter(|line| !line.trim_start().starts_with('#'))
        .filter_map(|line| {
            let (key, value) = line.split_once('=')?;
            Some((key.trim().to_string(), clean_tfvar(value)))
        })
        .collect())
}

/// Strip TOML/HCL decoration from a tfvars value. Lists (`["A", "B"]`) flatten
/// to the comma-separated form the relay parses.
fn clean_tfvar(value: &str) -> String {
    let value = value.split('#').next().unwrap_or(value).trim();
    if let Some(list) = value.strip_prefix('[').and_then(|v| v.strip_suffix(']')) {
        return list
            .split(',')
            .map(|item| item.trim().trim_matches('"'))
            .filter(|item| !item.is_empty())
            .collect::<Vec<_>>()
            .join(",");
    }
    value.trim_matches('"').to_string()
}

fn scw_config_get(key: &str) -> Option<String> {
    let out = Command::new("scw")
        .args(["config", "get", key])
        .output()
        .ok()?;
    out.status
        .success()
        .then(|| String::from_utf8_lossy(&out.stdout).trim().to_string())
}

fn git_short_head() -> Option<String> {
    let out = Command::new("git")
        .args(["rev-parse", "--short", "HEAD"])
        .output()
        .ok()?;
    out.status
        .success()
        .then(|| String::from_utf8_lossy(&out.stdout).trim().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn secrets(pairs: &[(&str, &str)]) -> Secrets {
        Secrets(
            pairs
                .iter()
                .map(|(k, v)| (k.to_string(), v.to_string()))
                .collect(),
        )
    }

    #[test]
    fn require_env_appends_the_suffix() {
        let s = secrets(&[("EIGIN_RELAY_PRIMARY_KEY_STAGING", "stg")]);
        assert_eq!(
            s.require_env("EIGIN_RELAY_PRIMARY_KEY", Env::Staging)
                .unwrap(),
            "stg"
        );
    }

    #[test]
    fn require_names_the_missing_key() {
        let err = secrets(&[]).require("STAAN_API_KEY_STAGING").unwrap_err();
        assert!(err.to_string().contains("STAAN_API_KEY_STAGING"));
    }

    #[test]
    fn require_treats_empty_as_missing() {
        assert!(secrets(&[("FOO", "")]).require("FOO").is_err());
    }

    #[test]
    fn placeholders_count_as_unset() {
        // Copying the template must never satisfy a check.
        let s = secrets(&[
            ("EIGIN_RELAY_PRIMARY_KEY_STAGING", "YOUR_SECRET_KEY"),
            ("DEVELOPMENT_TEAM", "TODO_TEAM_ID"),
        ]);
        assert!(s.get_env("EIGIN_RELAY_PRIMARY_KEY", Env::Staging).is_none());
        assert!(s.require("DEVELOPMENT_TEAM").is_err());
    }

    #[test]
    fn matching_skips_placeholder_values() {
        let s = secrets(&[
            ("PROVIDER_MISTRAL_API_KEY_STAGING", "real"),
            ("PROVIDER_BERGET_API_KEY_STAGING", "YOUR_SECRET_KEY"),
        ]);
        let found = s.matching("PROVIDER_", "_API_KEY_STAGING");
        assert_eq!(found, vec![("MISTRAL".to_string(), "real".to_string())]);
    }

    #[test]
    fn optional_is_empty_when_unset() {
        assert_eq!(secrets(&[]).optional_env("ROTATION", Env::Production), "");
    }

    #[test]
    fn matching_extracts_names_between_prefix_and_suffix() {
        let s = secrets(&[
            ("PROVIDER_TENSORX_API_KEY_STAGING", "a"),
            ("PROVIDER_MISTRAL_API_KEY_STAGING", "b"),
            ("PROVIDER_TENSORX_API_KEY_PRODUCTION", "c"),
            ("STAAN_API_KEY_STAGING", "d"),
        ]);
        let found = s.matching("PROVIDER_", "_API_KEY_STAGING");
        assert_eq!(
            found,
            vec![
                ("MISTRAL".to_string(), "b".to_string()),
                ("TENSORX".to_string(), "a".to_string())
            ]
        );
    }

    #[test]
    fn matching_ignores_an_empty_name() {
        let s = secrets(&[("PROVIDER__API_KEY_STAGING", "orphan")]);
        assert!(s.matching("PROVIDER_", "_API_KEY_STAGING").is_empty());
    }

    #[test]
    fn cleans_scalar_and_list_tfvars() {
        assert_eq!(clean_tfvar(" \"ai.eigin.finch\" "), "ai.eigin.finch");
        assert_eq!(clean_tfvar(" 25000 # a comment"), "25000");
        assert_eq!(
            clean_tfvar(" [\"Production\", \"Sandbox\"]"),
            "Production,Sandbox"
        );
    }
}
