//! Outer-layer tests: build a throwaway repo root on disk, then drive `resolve`
//! and each renderer the way the justfile does.

use std::fs;
use std::path::Path;
use tempfile::TempDir;

use eigin_tools::config;
use eigin_tools::config::model::Env;
use eigin_tools::config::render;
use eigin_tools::config::resolve::resolve;

const APP_TOML: &str = r#"
[identity]
bundle_id = "ai.example.app"

[contact]
support = "support@example"
alerts = "alerts@example"

[relay]
url.staging = "https://staging.example"
url.production = "https://example"

[oauth.google]
client_id.staging = "google-stg"
client_id.production = "google-prod"
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

const STAGING_TFVARS: &str = r#"
apple_bundle_id               = "ai.example.app.dev"
apple_app_apple_id            = ""
apple_environments            = ["Sandbox"]
sandbox_monthly_credit_budget = 5000
"#;

/// A repo root with committed config, optional secrets, and a staging tfvars.
fn repo(dot_env: Option<&str>) -> TempDir {
    let dir = TempDir::new().unwrap();
    let root = dir.path();
    fs::create_dir_all(root.join("config")).unwrap();
    fs::write(root.join("config/app.toml"), APP_TOML).unwrap();
    fs::write(
        root.join("config/tools.toml"),
        "[platforms.ios]\nlocalize.source = \"s\"\nlocalize.output = \"o\"\n",
    )
    .unwrap();

    let envs = root.join("infra/scaleway/environments");
    fs::create_dir_all(&envs).unwrap();
    fs::write(envs.join("staging.tfvars"), STAGING_TFVARS).unwrap();
    fs::write(envs.join("production.tfvars"), STAGING_TFVARS).unwrap();

    if let Some(contents) = dot_env {
        fs::write(root.join(".env"), contents).unwrap();
    }
    dir
}

fn root_of(dir: &TempDir) -> &str {
    dir.path().to_str().unwrap()
}

const FULL_ENV: &str = r#"
export DEVELOPMENT_TEAM=TEAM123
export EIGIN_RELAY_PRIMARY_KEY_STAGING=stg-relay
export EIGIN_RELAY_PRIMARY_KEY_PRODUCTION=prod-relay
export MOJEEK_API_KEY_STAGING=stg-mojeek
export MOJEEK_API_KEY_PRODUCTION=prod-mojeek
export PROVIDER_MISTRAL_API_KEY_STAGING=stg-mistral
export TFSTATE_ACCESS_KEY=scoped-access
export TFSTATE_SECRET_KEY=scoped-secret
export TFSTATE_REGION=nl-ams
"#;

// --- ios ---

#[test]
fn ios_renders_committed_config_and_secrets() {
    let dir = repo(Some(FULL_ENV));
    let r = resolve(root_of(&dir)).unwrap();
    let out = render::ios::render(&r);

    assert!(
        out.exports
            .contains("export EIGIN_RELAY_URL_STAGING='https://staging.example'")
    );
    assert!(
        out.exports
            .contains("export EIGIN_GOOGLE_OAUTH_CLIENT_ID_STAGING='google-stg'")
    );
    assert!(
        out.exports
            .contains("export EIGIN_RELAY_PRIMARY_KEY_PRODUCTION='prod-relay'")
    );
    assert!(out.exports.contains("export BUNDLE_ID='ai.example.app'"));
    assert!(
        out.exports
            .contains("export EIGIN_PRIVACY_URL='https://www.example/privacy/'")
    );
    assert!(
        out.exports
            .contains("export EIGIN_TERMS_URL='https://www.example/terms/'")
    );
    assert!(out.exports.contains("export DEVELOPMENT_TEAM='TEAM123'"));
    assert!(out.warnings.is_empty(), "{:?}", out.warnings);
}

#[test]
fn ios_builds_with_no_dot_env_at_all() {
    // The contributor path: no secrets, still a usable build.
    let dir = repo(None);
    let r = resolve(root_of(&dir)).unwrap();
    let out = render::ios::render(&r);

    assert!(
        out.exports
            .contains("export EIGIN_RELAY_URL_STAGING='https://staging.example'")
    );
    assert!(out.exports.contains(
        "export EIGIN_RELAY_PRIMARY_KEY_STAGING='MISSING_EIGIN_RELAY_PRIMARY_KEY_STAGING'"
    ));
    // Exported even when empty: xcodegen leaves a literal ${VAR} behind otherwise.
    assert!(out.exports.contains("export DEVELOPMENT_TEAM=''"));
    assert!(out.warnings.iter().any(|w| w.contains("DEVELOPMENT_TEAM")));
    assert!(
        out.warnings
            .iter()
            .any(|w| w.contains("EIGIN_RELAY_PRIMARY_KEY_PRODUCTION"))
    );
}

// --- relay ---

#[test]
fn relay_strips_suffixes_and_reads_tfvars() {
    let dir = repo(Some(FULL_ENV));
    let r = resolve(root_of(&dir)).unwrap();
    let out = render::relay::render(&r, Env::Staging, root_of(&dir)).unwrap();

    assert!(out.exports.contains("export MOJEEK_API_KEY='stg-mojeek'"));
    assert!(
        out.exports
            .contains("export EIGIN_RELAY_PRIMARY_KEY='stg-relay'")
    );
    assert!(
        out.exports
            .contains("export PROVIDER_MISTRAL_API_KEY='stg-mistral'")
    );
    assert!(
        out.exports
            .contains("export APPLE_BUNDLE_ID='ai.example.app.dev'")
    );
    assert!(out.exports.contains("export APPLE_ENVIRONMENTS='Sandbox'"));
}

#[test]
fn relay_fails_without_its_required_secrets() {
    let dir = repo(None);
    let r = resolve(root_of(&dir)).unwrap();
    let err = render::relay::render(&r, Env::Staging, root_of(&dir))
        .unwrap_err()
        .to_string();
    assert!(err.contains("MOJEEK_API_KEY_STAGING"), "{err}");
}

// --- tf-vars ---

#[test]
fn tf_vars_emits_terraform_and_aws_blocks() {
    let dir = repo(Some(FULL_ENV));
    let r = resolve(root_of(&dir)).unwrap();
    let out = render::tf_vars::render(&r, Env::Staging).unwrap().exports;

    assert!(out.contains("export TF_VAR_mojeek_api_key='stg-mojeek'"));
    assert!(out.contains("export TF_VAR_provider_api_keys='{\"mistral\":\"stg-mistral\"}'"));
    // Falls back to the config support address when no alerts inbox is set.
    assert!(out.contains("export TF_VAR_alerts_email='alerts@example'"));
    // The S3 remote-state backend block, preferring the scoped key from .env.
    assert!(out.contains("export AWS_ACCESS_KEY_ID='scoped-access'"));
    assert!(out.contains("export AWS_SECRET_ACCESS_KEY='scoped-secret'"));
    assert!(out.contains("export AWS_DEFAULT_REGION='nl-ams'"));
}

#[test]
fn relay_fails_loudly_when_a_tfvar_is_absent() {
    // A default here would be another environment's value — e.g. staging silently
    // running on the production credit budget.
    let dir = repo(Some(FULL_ENV));
    let envs = dir.path().join("infra/scaleway/environments");
    fs::write(
        envs.join("staging.tfvars"),
        "apple_bundle_id = \"x\"\napple_app_apple_id = \"\"\napple_environments = [\"Sandbox\"]\n",
    )
    .unwrap();

    let r = resolve(root_of(&dir)).unwrap();
    let err = render::relay::render(&r, Env::Staging, root_of(&dir))
        .unwrap_err()
        .to_string();
    assert!(err.contains("sandbox_monthly_credit_budget"), "{err}");
    assert!(err.contains("staging.tfvars"), "{err}");
}

#[test]
fn an_empty_tfvar_is_legitimate() {
    // apple_app_apple_id is intentionally blank in both committed files.
    let dir = repo(Some(FULL_ENV));
    let r = resolve(root_of(&dir)).unwrap();
    let out = render::relay::render(&r, Env::Staging, root_of(&dir)).unwrap();
    assert!(out.exports.contains("export APPLE_APP_APPLE_ID=''"));
}

#[test]
fn tf_vars_warns_about_placeholder_provider_keys() {
    // Half-filled .env must not deploy a quietly partial provider map.
    let dir = repo(Some(concat!(
        "export PROVIDER_MISTRAL_API_KEY_STAGING=real\n",
        "export PROVIDER_BERGET_API_KEY_STAGING=YOUR_SECRET_KEY\n",
    )));
    let r = resolve(root_of(&dir)).unwrap();
    let out = render::tf_vars::render(&r, Env::Staging).unwrap();

    assert!(out.exports.contains("'{\"mistral\":\"real\"}'"));
    assert!(
        out.warnings
            .iter()
            .any(|w| w.contains("PROVIDER_BERGET_API_KEY_STAGING")),
        "{:?}",
        out.warnings
    );
}

// --- placeholders ---

#[test]
fn placeholder_values_are_treated_as_unset_everywhere() {
    // Seeding .env from the template must not look like a configured repo.
    let dir = repo(Some(
        "export DEVELOPMENT_TEAM=YOUR_TEAM_ID\nexport MOJEEK_API_KEY_STAGING=YOUR_SECRET_KEY\n",
    ));
    let r = resolve(root_of(&dir)).unwrap();

    assert!(!render::ios::render(&r).warnings.is_empty());
    assert!(render::relay::render(&r, Env::Staging, root_of(&dir)).is_err());
}

#[test]
fn dot_env_quoting_and_comments_survive_the_public_path() {
    let dir = repo(Some(concat!(
        "# a comment\n\n",
        "export DEVELOPMENT_TEAM=\"quoted team\"\n",
        "EIGIN_RELAY_PRIMARY_KEY_STAGING='single quoted'\n",
    )));
    let r = resolve(root_of(&dir)).unwrap();
    let out = render::ios::render(&r).exports;

    assert!(out.contains("export DEVELOPMENT_TEAM='quoted team'"));
    assert!(out.contains("export EIGIN_RELAY_PRIMARY_KEY_STAGING='single quoted'"));
}

// --- init ---

#[test]
fn init_creates_dot_env_from_the_template() {
    let dir = repo(None);
    fs::write(dir.path().join(".env.example"), "export FOO=YOUR_VALUE\n").unwrap();

    config::init(root_of(&dir), false).unwrap();

    let written = fs::read_to_string(dir.path().join(".env")).unwrap();
    assert_eq!(written, "export FOO=YOUR_VALUE\n");
}

#[test]
fn init_refuses_to_clobber_an_existing_dot_env() {
    let dir = repo(Some("export FOO=my-real-secret\n"));
    fs::write(dir.path().join(".env.example"), "export FOO=YOUR_VALUE\n").unwrap();

    config::init(root_of(&dir), false).unwrap();

    let after = fs::read_to_string(dir.path().join(".env")).unwrap();
    assert_eq!(
        after, "export FOO=my-real-secret\n",
        "init overwrote a real .env"
    );
}

#[test]
fn init_force_replaces_an_existing_dot_env() {
    let dir = repo(Some("export FOO=stale\n"));
    fs::write(dir.path().join(".env.example"), "export FOO=YOUR_VALUE\n").unwrap();

    config::init(root_of(&dir), true).unwrap();

    let after = fs::read_to_string(dir.path().join(".env")).unwrap();
    assert_eq!(after, "export FOO=YOUR_VALUE\n");
}

#[test]
fn init_reports_a_missing_template() {
    let dir = repo(None);
    assert!(!Path::new(&dir.path().join(".env.example")).exists());
    assert!(config::init(root_of(&dir), false).is_err());
}
