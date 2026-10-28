//! Verify the static hosting contract over HTTPS.
use super::command;
use anyhow::{Context, Result, ensure};
use regex::Regex;
use std::{fs, path::Path};
use walkdir::WalkDir;

pub(super) fn validate_url(url: &str) -> Result<()> {
    ensure!(
        Regex::new(r"^https://[a-zA-Z0-9.-]+(:[0-9]+)?/?$")?.is_match(url),
        "WEBSITE_URL must be an HTTPS origin without credentials, path, or query"
    );
    Ok(())
}

pub(super) fn run(root: &Path, build: &Path, url: &str) -> Result<()> {
    validate_url(url)?;
    let url = url.trim_end_matches('/');
    command(
        root,
        "curl",
        &[
            "--fail",
            "--silent",
            "--show-error",
            "--location",
            "--max-time",
            "20",
            "--retry",
            "8",
            "--retry-all-errors",
            "--retry-delay",
            "5",
            "--retry-max-time",
            "120",
            "--output",
            "/dev/null",
            &format!("{url}/"),
        ],
        false,
    )?;
    for path in [
        "/privacy/",
        "/terms/",
        "/contact/",
        "/support/",
        "/",
        "/en/",
        "/da/",
        "/en/roadmap/",
        "/da/trust/",
        "/en/privacy/",
        "/da/terms/",
        "/en/contact/",
        "/da/support/",
    ] {
        let expected =
            fs::read_to_string(build.join(path.trim_start_matches('/')).join("index.html"))
                .with_context(|| format!("Read local HTML for {path}; build first"))?;
        let html = command(
            root,
            "curl",
            &[
                "--fail",
                "--silent",
                "--show-error",
                "--location",
                "--max-time",
                "30",
                &format!("{url}{path}"),
            ],
            true,
        )?;
        ensure!(
            html == expected.trim(),
            "Served HTML for {path} differs from the local build; check routing and CDN freshness"
        );
    }
    let redirect = command(
        root,
        "curl",
        &[
            "--silent",
            "--show-error",
            "--max-time",
            "30",
            "--output",
            "/dev/null",
            "--write-out",
            "%{http_code} %{redirect_url}",
            &format!("{url}/en"),
        ],
        true,
    )?;
    let (code, destination) = redirect
        .split_once(' ')
        .context("Missing slashless redirect")?;
    ensure!(
        ["301", "302", "307", "308"].contains(&code) && destination == format!("{url}/en/"),
        "Slashless route must redirect to {url}/en/: {redirect}"
    );
    for (extension, types) in [
        ("js", &["application/javascript", "text/javascript"][..]),
        ("css", &["text/css"][..]),
    ] {
        let mut assets = Vec::new();
        for entry in WalkDir::new(build.join("_app/immutable")) {
            let entry = entry?;
            if entry.file_type().is_file()
                && entry.path().extension().is_some_and(|ext| ext == extension)
            {
                assets.push(entry.into_path());
            }
        }
        assets.sort();
        let asset = assets
            .first()
            .with_context(|| format!("Build has no {extension} asset; build first"))?;
        let path = encode_path(&asset.strip_prefix(build)?.to_string_lossy());
        let mime = command(
            root,
            "curl",
            &[
                "--fail",
                "--silent",
                "--show-error",
                "--max-time",
                "30",
                "--output",
                "/dev/null",
                "--write-out",
                "%{content_type}",
                &format!("{url}/{path}"),
            ],
            true,
        )?;
        ensure!(
            types.contains(
                &mime
                    .split(';')
                    .next()
                    .unwrap_or("")
                    .trim()
                    .to_lowercase()
                    .as_str()
            ),
            "Unexpected MIME type for {path}: {mime}"
        );
    }
    let status = command(
        root,
        "curl",
        &[
            "--silent",
            "--show-error",
            "--max-time",
            "30",
            "--output",
            "/dev/null",
            "--write-out",
            "%{http_code}",
            &format!("{url}/__website_missing_page_check__/"),
        ],
        true,
    )?;
    ensure!(
        status == "404",
        "Missing route returned {status}, expected 404"
    );
    Ok(())
}

fn encode_path(path: &str) -> String {
    path.bytes()
        .map(|byte| {
            if byte.is_ascii_alphanumeric() || b"-._~/".contains(&byte) {
                (byte as char).to_string()
            } else {
                format!("%{byte:02X}")
            }
        })
        .collect()
}
