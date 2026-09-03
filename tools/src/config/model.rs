use serde::Deserialize;
use std::collections::HashMap;

/// A deployment environment. Most config and every secret is per-environment.
#[derive(Debug, Clone, Copy, PartialEq, Eq, clap::ValueEnum)]
pub enum Env {
    Staging,
    Production,
}

impl Env {
    /// Every environment, in the order renderers emit them.
    pub const ALL: [Env; 2] = [Env::Staging, Env::Production];

    /// The uppercase suffix used by environment-scoped variables.
    pub fn suffix(self) -> &'static str {
        match self {
            Env::Staging => "STAGING",
            Env::Production => "PRODUCTION",
        }
    }

    /// The lowercase name used by tfvars filenames and Terraform workspaces.
    pub fn as_str(self) -> &'static str {
        match self {
            Env::Staging => "staging",
            Env::Production => "production",
        }
    }
}

/// A value that differs per environment.
#[derive(Debug, Deserialize, Default)]
pub struct PerEnv<T> {
    pub staging: T,
    pub production: T,
}

impl<T> PerEnv<T> {
    pub fn get(&self, env: Env) -> &T {
        match env {
            Env::Staging => &self.staging,
            Env::Production => &self.production,
        }
    }
}

/// Shared, non-secret app configuration from `config/app.toml`.
#[derive(Debug, Deserialize)]
pub struct AppConfig {
    pub identity: Identity,
    pub contact: Contact,
    pub legal: LegalConfig,
    pub relay: RelayConfig,
    pub oauth: OAuthConfig,
    #[serde(default)]
    pub watermark: WatermarkConfig,
}

#[derive(Debug, Deserialize)]
pub struct Identity {
    pub bundle_id: String,
}

#[derive(Debug, Deserialize)]
pub struct Contact {
    pub support: String,
    pub alerts: String,
}

/// Legal pages linked from the app's About screen.
#[derive(Debug, Deserialize)]
pub struct LegalConfig {
    pub privacy: String,
    pub terms: String,
}

/// Watermark enablement for the build. Empty or absent `signature` disables
/// watermarking.
#[derive(Debug, Default, Deserialize)]
pub struct WatermarkConfig {
    #[serde(default)]
    pub signature: String,
}

#[derive(Debug, Deserialize)]
pub struct RelayConfig {
    pub url: PerEnv<String>,
}

#[derive(Debug, Deserialize)]
pub struct OAuthConfig {
    pub google: OAuthClient,
    pub microsoft: OAuthClient,
    pub aula: OAuthClient,
}

/// A PKCE mobile OAuth client. The id is public by design; there is no secret.
#[derive(Debug, Deserialize)]
pub struct OAuthClient {
    #[serde(default)]
    pub client_id: PerEnv<String>,
}

/// Tooling configuration from `config/tools.toml`.
#[derive(Debug, Deserialize)]
pub struct ToolsConfig {
    pub platforms: HashMap<String, PlatformConfig>,
}

#[derive(Debug, Deserialize)]
pub struct PlatformConfig {
    pub localize: Option<LocalizeConfig>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct LocalizeConfig {
    pub source: String,
    pub output: String,
    pub formatter: Option<String>,
    #[serde(rename = "validate-sources")]
    pub validate_sources: Option<String>,
}

/// Everything committed under `config/`.
#[derive(Debug)]
pub struct Config {
    pub app: AppConfig,
    pub tools: ToolsConfig,
}
