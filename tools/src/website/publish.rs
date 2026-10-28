//! Validate destinations and publish assets before HTML.
use super::execute;
use anyhow::{Result, ensure};
use regex::Regex;
use std::{path::Path, process::Command};

pub(super) struct Target {
    pub bucket: String,
    pub endpoint: String,
    pub url: String,
}

impl Target {
    pub fn new(bucket: String, endpoint: String, url: String) -> Result<Self> {
        ensure!(
            Regex::new(r"^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$")?.is_match(&bucket),
            "Invalid website bucket in Terraform output"
        );
        ensure!(
            bucket != "eigin-website",
            "The old live bucket is not a deployment target"
        );
        ensure!(
            Regex::new(r"^https://s3\.(fr-par|nl-ams|pl-waw)\.scw\.cloud$")?.is_match(&endpoint),
            "Invalid Scaleway S3 endpoint"
        );
        super::verify::validate_url(&url)?;
        Ok(Self {
            bucket,
            endpoint,
            url,
        })
    }
}

// Credentials stay in memory and child environments, never logs or command arguments.
pub(super) struct Credentials {
    pub access_key: String,
    pub secret_key: String,
}

pub(super) fn run(
    root: &Path,
    build: &Path,
    target: &Target,
    credentials: &Credentials,
) -> Result<()> {
    let destination = format!("s3://{}/", target.bucket);
    let upload = |source: &Path, destination: &str, options: &[&str]| -> Result<()> {
        execute(
            Command::new("aws")
                .current_dir(root)
                .args(["--endpoint-url", &target.endpoint, "s3", "cp"])
                .arg(format!("{}/", source.display()))
                .arg(destination)
                .arg("--recursive")
                .args(options)
                .env("AWS_ACCESS_KEY_ID", &credentials.access_key)
                .env("AWS_SECRET_ACCESS_KEY", &credentials.secret_key)
                .env_remove("AWS_SESSION_TOKEN")
                .env_remove("AWS_SECURITY_TOKEN")
                .env_remove("AWS_PROFILE")
                .env_remove("AWS_DEFAULT_PROFILE"),
            false,
        )?;
        Ok(())
    };
    let immutable = build.join("_app/immutable");
    ensure!(immutable.is_dir(), "Build has no immutable assets");
    upload(
        &immutable,
        &format!("{destination}_app/immutable/"),
        &["--cache-control", "public,max-age=31536000,immutable"],
    )?;
    upload(
        build,
        &destination,
        &[
            "--exclude",
            "_app/immutable/*",
            "--exclude",
            "*.html",
            "--cache-control",
            "no-cache,max-age=0,must-revalidate",
        ],
    )?;
    upload(
        build,
        &destination,
        &[
            "--exclude",
            "*",
            "--include",
            "*.html",
            "--content-type",
            "text/html; charset=utf-8",
            "--cache-control",
            "no-cache,max-age=0,must-revalidate",
        ],
    )
}
