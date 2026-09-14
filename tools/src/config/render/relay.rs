use anyhow::{Context, Result};

use super::Rendered;
use super::shell::export;
use crate::config::model::Env;
use crate::config::resolve::{Resolved, tfvars};

/// Render the runtime environment for a locally run relay.
///
/// Secrets are stored per environment and stripped of their suffix here, because
/// the relay reads unsuffixed names. Non-secret runtime values come from the
/// environment's tfvars, which stays Terraform's source of truth. Every secret
/// here is required: a relay can't serve without its search and auth keys.
pub fn render(r: &Resolved, env: Env, repo_root: &str) -> Result<Rendered> {
    let mut out = String::new();

    export(
        &mut out,
        "STAAN_API_KEY",
        r.secrets.require_env("STAAN_API_KEY", env)?,
    );
    export(
        &mut out,
        "EIGIN_RELAY_PRIMARY_KEY",
        r.secrets.require_env("EIGIN_RELAY_PRIMARY_KEY", env)?,
    );
    export(
        &mut out,
        "EIGIN_RELAY_SECONDARY_KEY",
        r.secrets.optional_env("EIGIN_RELAY_SECONDARY_KEY", env),
    );

    for (name, value) in r
        .secrets
        .matching("PROVIDER_", &format!("_API_KEY_{}", env.suffix()))
    {
        export(&mut out, &format!("PROVIDER_{name}_API_KEY"), &value);
    }

    // Read the file once; the relay needs several values out of it. An absent key
    // is an error rather than a default: any stand-in would be another
    // environment's value, and running staging on production limits is worse than
    // refusing to start. Present-but-empty is legitimate.
    let tfvars = tfvars(repo_root, env)?;
    for (var, key) in [
        ("APPLE_BUNDLE_ID", "apple_bundle_id"),
        ("APPLE_APP_APPLE_ID", "apple_app_apple_id"),
        ("APPLE_ENVIRONMENTS", "apple_environments"),
        (
            "SANDBOX_MONTHLY_CREDIT_BUDGET",
            "sandbox_monthly_credit_budget",
        ),
    ] {
        let value = tfvars.get(key).with_context(|| {
            format!(
                "{key} missing from infra/scaleway/environments/{}.tfvars",
                env.as_str()
            )
        })?;
        export(&mut out, var, value);
    }

    Ok(Rendered::new(out, Vec::new()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::test_support::{repo_with_tfvars, resolved};

    fn full_secrets() -> Vec<(&'static str, &'static str)> {
        vec![
            ("STAAN_API_KEY_STAGING", "staan-stg"),
            ("EIGIN_RELAY_PRIMARY_KEY_STAGING", "relay-stg"),
            ("PROVIDER_MISTRAL_API_KEY_STAGING", "mistral-stg"),
        ]
    }

    #[test]
    fn strips_the_environment_suffix() {
        let dir = repo_with_tfvars();
        let out = render(
            &resolved(&full_secrets()),
            Env::Staging,
            dir.path().to_str().unwrap(),
        )
        .unwrap()
        .exports;
        assert!(out.contains("export STAAN_API_KEY='staan-stg'"));
        assert!(out.contains("export EIGIN_RELAY_PRIMARY_KEY='relay-stg'"));
        assert!(out.contains("export PROVIDER_MISTRAL_API_KEY='mistral-stg'"));
    }

    #[test]
    fn reads_non_secret_values_from_tfvars() {
        let dir = repo_with_tfvars();
        let out = render(
            &resolved(&full_secrets()),
            Env::Staging,
            dir.path().to_str().unwrap(),
        )
        .unwrap()
        .exports;
        assert!(out.contains("export APPLE_BUNDLE_ID='ai.example.app.dev'"));
        // List-valued tfvars flatten to the comma-separated form the relay parses.
        assert!(out.contains("export APPLE_ENVIRONMENTS='Sandbox'"));
        assert!(out.contains("export SANDBOX_MONTHLY_CREDIT_BUDGET='5000'"));
    }

    #[test]
    fn empty_tfvar_falls_back_to_the_default() {
        let dir = repo_with_tfvars();
        let out = render(
            &resolved(&full_secrets()),
            Env::Staging,
            dir.path().to_str().unwrap(),
        )
        .unwrap()
        .exports;
        assert!(out.contains("export APPLE_APP_APPLE_ID=''"));
    }

    #[test]
    fn fails_when_a_required_secret_is_missing() {
        let dir = repo_with_tfvars();
        let err = render(&resolved(&[]), Env::Staging, dir.path().to_str().unwrap())
            .unwrap_err()
            .to_string();
        assert!(err.contains("STAAN_API_KEY_STAGING"));
    }
}
