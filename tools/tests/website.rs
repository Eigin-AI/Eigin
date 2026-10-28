//! Exercise the real CLI with fake cloud/process boundaries.
use std::{
    fs,
    io::Write,
    os::unix::fs::PermissionsExt,
    path::Path,
    process::{Command, Output, Stdio},
};
use tempfile::TempDir;

struct Site {
    dir: TempDir,
}

impl Site {
    fn new() -> Self {
        let dir = TempDir::new().unwrap();
        let root = dir.path();
        fs::create_dir(root.join("bin")).unwrap();
        fs::create_dir_all(root.join("infra/scaleway")).unwrap();
        fs::write(root.join("infra/scaleway/backend.tf"), "").unwrap();
        let build = root.join("src/eigin_website/build");
        fs::create_dir_all(build.join("_app/immutable")).unwrap();
        fs::write(build.join("index.html"), "home").unwrap();
        for locale in ["en", "da"] {
            for slug in [
                "", "roadmap", "trust", "privacy", "terms", "contact", "support",
            ] {
                let page = build.join(format!("{locale}/{slug}/index.html"));
                fs::create_dir_all(page.parent().unwrap()).unwrap();
                fs::write(page, format!("<html><body>{locale}/{slug}</body></html>")).unwrap();
            }
        }
        for slug in ["privacy", "terms", "contact", "support"] {
            let page = build.join(format!("{slug}/index.html"));
            fs::create_dir_all(page.parent().unwrap()).unwrap();
            fs::write(
                page,
                format!(r#"<meta http-equiv="refresh" content="0;url=/en/{slug}/">"#),
            )
            .unwrap();
        }
        for ext in ["js", "css"] {
            fs::write(build.join(format!("_app/immutable/test.{ext}")), "asset").unwrap();
        }
        let script = r#"#!/bin/sh
set -eu
name=$(basename "$0")
[ "$name" != git ] || { pwd; exit 0; }
printf '%s %s\n' "$name" "$*" >> "$TEST_LOG"
case "$name" in
  terraform)
    [ "${TF_WORKSPACE:-}" = production ] || exit 10
    case "$*" in
      *" init "*) [ "${FAIL_STEP:-}" != init ] || exit 8 ;;
      *" output "*) [ "${FAIL_STEP:-}" != output ] || exit 8 ;;
    esac
    case "$*" in
      *website_upload_access_key) printf 'test-publisher' ;;
      *website_upload_secret_key) printf 'test-publisher-secret' ;;
      *bucket_name) printf '%s' "${WEBSITE_BUCKET:-new-website}" ;;
      *s3_endpoint) printf '%s' "${WEBSITE_ENDPOINT:-https://s3.fr-par.scw.cloud}" ;;
      *preview_url) printf '%s' "${WEBSITE_URL:-https://preview.example.com}" ;;
    esac ;;
  aws)
    [ "${AWS_ACCESS_KEY_ID:-}" = test-publisher ] || exit 9
    [ "${AWS_SECRET_ACCESS_KEY:-}" = test-publisher-secret ] || exit 9
    [ -z "${AWS_SESSION_TOKEN:-}${AWS_SECURITY_TOKEN:-}${AWS_PROFILE:-}${AWS_DEFAULT_PROFILE:-}" ] || exit 9
    [ "${FAIL_STEP:-}" != upload ] || exit 8 ;;
  tar) exec /usr/bin/tar "$@" ;;
  curl)
    case "$*" in
      *'%{redirect_url}'*) printf '%s' "${REDIRECT:-301 https://preview.example.com/en/}" ;;
      *'%{content_type}'*.js) printf '%s' "${JS_MIME:-application/javascript}" ;;
      *'%{content_type}'*.css) printf 'text/css' ;;
      *'%{http_code}'*) printf '%s' "${MISSING_STATUS:-404}" ;;
      *'--output /dev/null'*) ;;
      *)
        for url do :; done
        path=${url#https://preview.example.com}
        if [ "$path" = "${WRONG_HTML_PATH:-}" ]; then
          printf '%s' "${WRONG_HTML:-<html>Error</html>}"
        else
          cat "src/eigin_website/build${path}index.html"
        fi ;;
    esac ;;
esac
"#;
        for name in ["git", "just", "npm", "terraform", "aws", "curl", "tar"] {
            let file = root.join("bin").join(name);
            fs::write(&file, script).unwrap();
            fs::set_permissions(file, fs::Permissions::from_mode(0o755)).unwrap();
        }
        Self { dir }
    }

    fn root(&self) -> &Path {
        self.dir.path()
    }

    fn run(&self, action: &str, input: &str, vars: &[(&str, &str)]) -> Output {
        let mut command = Command::new(env!("CARGO_BIN_EXE_eigin-tools"));
        command
            .current_dir(self.root())
            .args(["website", action])
            .env(
                "PATH",
                format!("{}:/usr/bin:/bin", self.root().join("bin").display()),
            )
            .env("TEST_LOG", self.root().join("commands.log"))
            .env("WEBSITE_BUCKET", "new-website")
            .env("WEBSITE_ENDPOINT", "https://s3.fr-par.scw.cloud")
            .env("WEBSITE_URL", "https://preview.example.com")
            .env("TF_WORKSPACE", "staging")
            .env("AWS_PROFILE", "state-profile")
            .env("AWS_ACCESS_KEY_ID", "test-admin")
            .env("AWS_SECRET_ACCESS_KEY", "test-secret")
            .env("AWS_SESSION_TOKEN", "test-token")
            .env("AWS_SECURITY_TOKEN", "test-legacy-token")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        for (key, value) in vars {
            command.env(key, value);
        }
        let mut child = command.spawn().unwrap();
        child
            .stdin
            .take()
            .unwrap()
            .write_all(input.as_bytes())
            .unwrap();
        child.wait_with_output().unwrap()
    }

    fn log(&self) -> String {
        fs::read_to_string(self.root().join("commands.log")).unwrap_or_default()
    }
}

#[test]
fn website_release_uploads_assets_before_html_with_scoped_credentials() {
    let site = Site::new();
    let output = site.run("release", "yes\n", &[]);
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let log = site.log();
    assert!(log.contains("terraform"));
    let uploads: Vec<_> = log
        .lines()
        .filter(|line| line.starts_with("aws "))
        .collect();
    assert_eq!(uploads.len(), 3);
    assert!(uploads[0].contains("public,max-age=31536000,immutable"));
    assert!(uploads[1].contains("--exclude *.html"));
    assert!(uploads[2].contains("--include *.html --content-type text/html; charset=utf-8"));
    assert!(
        uploads
            .iter()
            .all(|line| !line.contains("--profile") && !line.contains("--delete"))
    );
    let releases = site.root().join("infra/scaleway/website-releases");
    let receipt = fs::read_dir(&releases)
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .find(|path| path.extension().is_some_and(|ext| ext == "json"))
        .unwrap();
    let record: serde_json::Value = serde_json::from_slice(&fs::read(receipt).unwrap()).unwrap();
    assert!(releases.join(record["archive"].as_str().unwrap()).is_file());
    assert_eq!(record["url"], "https://preview.example.com");
    assert!(record["verified_at_unix_seconds"].as_u64().unwrap() > 0);
    for slug in ["privacy", "terms", "contact", "support"] {
        let page = fs::read_to_string(
            site.root()
                .join(format!("src/eigin_website/build/{slug}/index.html")),
        )
        .unwrap();
        assert!(page.contains(&format!("0;url=/en/{slug}/")));
    }
}

#[test]
fn website_release_reads_production_outputs_without_infrastructure_changes() {
    let site = Site::new();
    let output = site.run("release", "yes\n", &[]);
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let log = site.log();
    assert!(log.contains("output -raw website_bucket_name"));
    assert!(log.contains("output -raw website_upload_secret_key"));
    assert!(!log.contains(" plan "));
    assert!(!log.contains(" apply "));
    assert!(!log.contains("workspace select"));
    for bytes in [&output.stdout, &output.stderr] {
        assert!(!String::from_utf8_lossy(bytes).contains("test-publisher"));
    }
}

#[test]
fn website_failed_init_or_missing_outputs_never_publishes() {
    for step in ["init", "output"] {
        let site = Site::new();
        assert!(
            !site
                .run("release", "yes\n", &[("FAIL_STEP", step)])
                .status
                .success()
        );
        assert!(!site.log().contains("aws "));
        assert!(!site.log().contains("npm "));
    }
}

#[test]
fn website_declined_confirmation_stops_mutation() {
    for (action, input) in [("release", "y\n"), ("release", "no\n")] {
        let site = Site::new();
        assert!(!site.run(action, input, &[]).status.success());
        assert!(!site.log().contains("aws "));
        assert!(!site.log().contains("apply -input=false"));
    }
}

#[test]
fn website_failed_upload_stops_before_html_and_verification() {
    let site = Site::new();
    assert!(
        !site
            .run("release", "yes\n", &[("FAIL_STEP", "upload")])
            .status
            .success()
    );
    assert_eq!(
        site.log()
            .lines()
            .filter(|line| line.starts_with("aws "))
            .count(),
        1
    );
    assert!(!site.log().contains("curl "));
}

#[test]
fn website_rejects_old_bucket_and_untrusted_endpoint() {
    for pair in [
        ("WEBSITE_BUCKET", "eigin-website"),
        ("WEBSITE_ENDPOINT", "https://example.com"),
        ("WEBSITE_URL", "https://user:pass@example.com"),
    ] {
        let site = Site::new();
        assert!(!site.run("release", "yes\n", &[pair]).status.success());
        assert!(!site.log().contains("aws "));
    }
}

#[test]
fn website_verification_rejects_bad_redirect_mime_and_missing_page() {
    for pair in [
        ("REDIRECT", "200 "),
        ("JS_MIME", "text/html"),
        ("MISSING_STATUS", "200"),
    ] {
        let site = Site::new();
        assert!(!site.run("verify", "", &[pair]).status.success());
        assert!(!site.log().contains("aws "));
    }
}

#[test]
fn website_empty_publisher_key_fails_before_build() {
    let site = Site::new();
    let terraform = site.root().join("bin/terraform");
    let script = fs::read_to_string(&terraform)
        .unwrap()
        .replace("printf 'test-publisher-secret'", "printf ''");
    fs::write(&terraform, script).unwrap();
    assert!(!site.run("release", "yes\n", &[]).status.success());
    assert!(!site.log().contains("npm "));
    assert!(!site.log().contains("aws "));
}

#[test]
fn website_failed_or_cancelled_publish_has_no_success_receipt() {
    for (input, vars) in [
        ("no\n", vec![]),
        ("yes\n", vec![("FAIL_STEP", "upload")]),
        ("yes\n", vec![("JS_MIME", "text/html")]),
        ("yes\n", vec![("WRONG_HTML_PATH", "/en/roadmap/")]),
        ("yes\n", vec![("WRONG_HTML_PATH", "/privacy/")]),
    ] {
        let site = Site::new();
        assert!(!site.run("release", input, &vars).status.success());
        let releases = site.root().join("infra/scaleway/website-releases");
        assert!(fs::read_dir(releases).unwrap().all(|entry| {
            entry
                .unwrap()
                .path()
                .extension()
                .is_none_or(|ext| ext != "json")
        }));
    }
}

#[test]
fn website_asset_regeneration_requires_brand_fonts_without_overwriting_artwork() {
    let site = Site::new();
    fs::create_dir_all(site.root().join("design/assets/icons/brand")).unwrap();
    fs::write(
        site.root().join("design/tokens.json"),
        include_str!("../../design/tokens.json"),
    )
    .unwrap();
    fs::write(
        site.root().join("design/assets/icons/brand/avatar.svg"),
        include_str!("../../design/assets/icons/brand/avatar.svg"),
    )
    .unwrap();
    let icon = site.root().join("src/eigin_website/static/favicon.svg");
    fs::create_dir_all(icon.parent().unwrap()).unwrap();
    fs::write(&icon, "existing committed icon").unwrap();
    let output = site.run("assets", "", &[]);
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("Install brand font"));
    assert_eq!(fs::read_to_string(icon).unwrap(), "existing committed icon");
    assert!(!site.log().contains("terraform "));
    assert!(!site.log().contains("aws "));
}

#[test]
fn website_verification_rejects_wrong_html_with_successful_http_status() {
    for (path, html) in [
        ("/en/roadmap/", "home"),
        ("/da/trust/", "<html>Error</html>"),
        (
            "/privacy/",
            r#"<meta http-equiv="refresh" content="0;url=/en/terms/">"#,
        ),
    ] {
        let site = Site::new();
        let output = site.run(
            "verify",
            "",
            &[("WRONG_HTML_PATH", path), ("WRONG_HTML", html)],
        );
        assert!(!output.status.success());
        assert!(
            String::from_utf8_lossy(&output.stderr)
                .contains(&format!("Served HTML for {path} differs"))
        );
    }
}

#[test]
fn website_verification_accepts_matching_html() {
    let site = Site::new();
    let output = site.run("verify", "", &[]);
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
}
