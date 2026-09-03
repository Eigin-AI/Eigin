use super::Rendered;
use super::shell::export;
use crate::config::model::Env;
use crate::config::resolve::Resolved;

/// Render the environment the iOS toolchain needs, for xcodegen and fastlane.
///
/// Emits both environments at once: `project.yml` defines the Eigin and EiginDev
/// targets side by side, referencing `${EIGIN_RELAY_URL_PRODUCTION}` and
/// `${EIGIN_RELAY_URL_STAGING}` in the same generate run.
/// Always succeeds: every value here is a runtime or signing concern, so a
/// contributor without them still gets a working simulator build. Missing values
/// warn and render a self-describing placeholder.
pub fn render(r: &Resolved) -> Rendered {
    let app = &r.config.app;
    let mut out = String::new();
    let mut warnings = Vec::new();

    for env in Env::ALL {
        let suffix = env.suffix();
        let oauth = &app.oauth;
        for (name, configured) in [
            ("EIGIN_GOOGLE_OAUTH_CLIENT_ID", &oauth.google.client_id),
            (
                "EIGIN_MICROSOFT_OAUTH_CLIENT_ID",
                &oauth.microsoft.client_id,
            ),
            ("EIGIN_AULA_OAUTH_CLIENT_ID", &oauth.aula.client_id),
        ] {
            export(&mut out, &format!("{name}_{suffix}"), configured.get(env));
        }
        export(
            &mut out,
            &format!("EIGIN_RELAY_URL_{suffix}"),
            app.relay.url.get(env),
        );
        // Baked into the app so it can authenticate against the relay.
        let key = format!("EIGIN_RELAY_PRIMARY_KEY_{suffix}");
        let value = match r.secrets.get_env("EIGIN_RELAY_PRIMARY_KEY", env) {
            Some(value) => value.to_string(),
            None => {
                warnings.push(format!(
                    "{key} not set — the {} app will build, but relay features (inference, search, credits) won't work",
                    env.as_str()
                ));
                format!("MISSING_{key}")
            }
        };
        export(&mut out, &key, &value);
    }

    export(&mut out, "EIGIN_SUPPORT_EMAIL", &app.contact.support);
    export(&mut out, "EIGIN_PRIVACY_URL", &app.legal.privacy);
    export(&mut out, "EIGIN_TERMS_URL", &app.legal.terms);
    export(
        &mut out,
        "EIGIN_WATERMARK_SIGNATURE",
        &app.watermark.signature,
    );
    export(&mut out, "BUNDLE_ID", &app.identity.bundle_id);

    // Per-contributor: each developer signs with their own Apple team. Simulator
    // builds don't need signing, so an empty team is fine until you build for a
    // device.
    //
    // Exported even when empty, deliberately: xcodegen substitutes `${VAR}` from
    // the environment, and leaves the literal `${DEVELOPMENT_TEAM}` in the
    // generated project when the variable is absent. Empty resolves correctly.
    // `just release` asserts a real value before signing.
    let team = r.secrets.get("DEVELOPMENT_TEAM").unwrap_or_else(|| {
        warnings.push(
            "DEVELOPMENT_TEAM not set — simulator builds work, device builds and releases won't"
                .to_string(),
        );
        ""
    });
    export(&mut out, "DEVELOPMENT_TEAM", team);

    // Release-only. Absent for ordinary builds, so never required here; the
    // fastlane lanes that need them fail loudly on their own.
    for key in [
        "ASC_KEY_ID",
        "ASC_ISSUER_ID",
        "ASC_KEY_PATH",
        "APP_REVIEW_FIRST_NAME",
        "APP_REVIEW_LAST_NAME",
        "APP_REVIEW_PHONE_NUMBER",
    ] {
        let value = r.secrets.optional(key);
        if !value.is_empty() {
            export(&mut out, key, value);
        }
    }

    Rendered::new(out, warnings)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::test_support::{APP_TOML, resolved, resolved_from};

    fn base() -> Vec<(&'static str, &'static str)> {
        vec![
            ("EIGIN_RELAY_PRIMARY_KEY_STAGING", "stg-key"),
            ("EIGIN_RELAY_PRIMARY_KEY_PRODUCTION", "prod-key"),
            ("DEVELOPMENT_TEAM", "TEAM123"),
        ]
    }

    #[test]
    fn emits_both_environments() {
        let out = render(&resolved(&base())).exports;
        assert!(out.contains("export EIGIN_RELAY_URL_STAGING='https://staging.example'"));
        assert!(out.contains("export EIGIN_RELAY_URL_PRODUCTION='https://example'"));
        assert!(out.contains("export EIGIN_RELAY_PRIMARY_KEY_STAGING='stg-key'"));
        assert!(out.contains("export DEVELOPMENT_TEAM='TEAM123'"));
    }

    #[test]
    fn a_contributor_with_no_secrets_can_still_build() {
        // The whole point of the OSS path: no .env, no relay key, still builds.
        let rendered = render(&resolved(&[]));
        assert!(rendered.exports.contains("export EIGIN_RELAY_URL_STAGING="));
        assert!(
            rendered
                .exports
                .contains("export BUNDLE_ID='ai.example.app'")
        );
    }

    #[test]
    fn missing_relay_key_warns_and_bakes_a_self_describing_value() {
        // Never an empty string: a runtime failure should name its own cause.
        let rendered = render(&resolved(&[]));
        assert!(rendered.exports.contains(
            "export EIGIN_RELAY_PRIMARY_KEY_STAGING='MISSING_EIGIN_RELAY_PRIMARY_KEY_STAGING'"
        ));
        assert!(
            rendered
                .warnings
                .iter()
                .any(|w| w.contains("EIGIN_RELAY_PRIMARY_KEY_STAGING"))
        );
    }

    #[test]
    fn placeholder_secrets_are_treated_as_missing() {
        // `config init` seeds these; copying the template must not look configured.
        let rendered = render(&resolved(&[
            ("EIGIN_RELAY_PRIMARY_KEY_STAGING", "YOUR_SECRET_KEY"),
            ("DEVELOPMENT_TEAM", "YOUR_TEAM_ID"),
        ]));
        assert!(
            rendered
                .warnings
                .iter()
                .any(|w| w.contains("DEVELOPMENT_TEAM"))
        );
        assert!(
            rendered
                .warnings
                .iter()
                .any(|w| w.contains("EIGIN_RELAY_PRIMARY_KEY_STAGING"))
        );
        assert!(rendered.exports.contains("export DEVELOPMENT_TEAM=''"));
    }

    #[test]
    fn no_warnings_when_fully_configured() {
        assert!(render(&resolved(&base())).warnings.is_empty());
    }

    #[test]
    fn bundle_id_comes_from_config() {
        let out = render(&resolved(&base())).exports;
        assert!(out.contains("export BUNDLE_ID='ai.example.app'"));
    }

    #[test]
    fn omits_release_only_values_when_unset() {
        assert!(!render(&resolved(&base())).exports.contains("ASC_KEY_ID"));
    }

    #[test]
    fn a_secret_containing_shell_metacharacters_is_not_expanded() {
        let mut secrets = base();
        secrets.push(("ASC_KEY_ID", "ab$HOME`echo x`"));
        let out = render(&resolved(&secrets)).exports;
        assert!(out.contains(r"export ASC_KEY_ID='ab$HOME`echo x`'"));
    }
}
