use super::{Rendered, shell::export};
use crate::config::resolve::Resolved;

/// Export local contributor portal settings under the server's runtime names.
pub fn render(r: &Resolved) -> Rendered {
    let mut out = String::new();
    for (name, value) in environment(r) {
        export(&mut out, name, value);
    }
    Rendered::new(out, Vec::new())
}

/// Resolve the allowlist shared by the shell export and the web runner.
pub fn environment(r: &Resolved) -> Vec<(&'static str, &str)> {
    vec![
        (
            "GITLAB_CLIENT_ID",
            r.secrets.optional("CONTRIBUTORS_GITLAB_CLIENT_ID"),
        ),
        (
            "GITLAB_CLIENT_SECRET",
            r.secrets.optional("CONTRIBUTORS_GITLAB_CLIENT_SECRET"),
        ),
        (
            "REVIEWER_GITLAB_IDS",
            r.secrets.optional("CONTRIBUTORS_REVIEWER_GITLAB_IDS"),
        ),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::test_support::resolved;

    #[test]
    fn exports_only_portal_settings_under_runtime_names() {
        let out = render(&resolved(&[
            (
                "CONTRIBUTORS_DATABASE_URL",
                "postgresql://localhost/contributors",
            ),
            ("CONTRIBUTORS_ORIGIN", "http://ignored.example"),
            ("CONTRIBUTORS_GITLAB_CLIENT_ID", "client"),
            ("CONTRIBUTORS_GITLAB_CLIENT_SECRET", "literal'$HOME"),
            ("CONTRIBUTORS_REVIEWER_GITLAB_IDS", "10,20"),
            (
                "TEST_DATABASE_URL",
                "postgresql://localhost/contributors_test",
            ),
            ("ANOTHER_SECRET", "unrelated"),
        ]))
        .exports;
        assert_eq!(
            out,
            concat!(
                "export GITLAB_CLIENT_ID='client'\n",
                "export GITLAB_CLIENT_SECRET='literal'\\''$HOME'\n",
                "export REVIEWER_GITLAB_IDS='10,20'\n",
            )
        );
    }

    #[test]
    fn allows_signed_out_setup() {
        let out = render(&resolved(&[])).exports;
        assert!(out.contains("export GITLAB_CLIENT_SECRET=''"));
        assert!(out.contains("export REVIEWER_GITLAB_IDS=''"));
    }
}
