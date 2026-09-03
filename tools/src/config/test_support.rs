//! Fixtures for renderer tests: a small config and a fake `.env`.

use std::collections::HashMap;
use std::fs;
use tempfile::TempDir;

use super::model::*;
use super::resolve::{Resolved, Secrets};

pub const APP_TOML: &str = r#"
[identity]
bundle_id = "ai.example.app"

[contact]
support = "support@example"
alerts = "alerts@example"

[relay]
url.staging = "https://staging.example"
url.production = "https://example"

[oauth.google]
client_id.staging = ""
client_id.production = ""
[oauth.microsoft]
client_id.staging = ""
client_id.production = ""
[oauth.aula]
client_id.staging = ""
client_id.production = ""

[legal]
privacy = "https://www.example/privacy/"
terms = "https://www.example/terms/"
"#;

/// A `Resolved` backed by the fixture config and the given secrets.
pub fn resolved(secrets: &[(&str, &str)]) -> Resolved {
    resolved_from(APP_TOML, secrets)
}

/// A `Resolved` built from a custom `app.toml`, for testing config precedence.
pub fn resolved_from(app_toml: &str, secrets: &[(&str, &str)]) -> Resolved {
    let pairs: HashMap<String, String> = secrets
        .iter()
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect();
    Resolved {
        config: Config {
            app: toml::from_str(app_toml).expect("fixture app.toml"),
            tools: ToolsConfig {
                platforms: HashMap::new(),
            },
        },
        secrets: Secrets::from_map(pairs),
    }
}

/// A temp repo root containing a staging tfvars file.
pub fn repo_with_tfvars() -> TempDir {
    let dir = TempDir::new().unwrap();
    let envs = dir.path().join("infra/scaleway/environments");
    fs::create_dir_all(&envs).unwrap();
    fs::write(
        envs.join("staging.tfvars"),
        concat!(
            "apple_bundle_id               = \"ai.example.app.dev\"\n",
            "apple_app_apple_id            = \"\"\n",
            "apple_environments = [\"Sandbox\"]\n",
            "sandbox_monthly_credit_budget = 5000\n",
        ),
    )
    .unwrap();
    dir
}
