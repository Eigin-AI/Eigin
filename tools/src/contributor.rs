use anyhow::{Context, Result, bail, ensure};
use clap::Subcommand;
use serde::Deserialize;
use serde_json::Value;
use std::{
    fs,
    process::Command,
    time::{SystemTime, UNIX_EPOCH},
};

#[derive(clap::Args)]
pub struct Args {
    #[command(subcommand)]
    action: Action,
}

#[derive(Subcommand)]
enum Action {
    /// Finish an operator-confirmed production infrastructure deployment.
    AfterApply,
    Rollback {
        digest: String,
    },
}

#[derive(Deserialize)]
struct Hosting {
    project: String,
    region: String,
    digest: String,
    repo: String,
    service: String,
    migrate: String,
    prune: String,
}

fn captured(cmd: &mut Command) -> Result<String> {
    let output = cmd.output()?;
    ensure!(
        output.status.success(),
        "{} failed: {}",
        cmd.get_program().to_string_lossy(),
        output.status
    );
    Ok(String::from_utf8(output.stdout)?.trim().to_owned())
}

fn valid_digest(digest: &str) -> bool {
    digest.strip_prefix("sha256:").is_some_and(|d| {
        d.len() == 64
            && d.bytes()
                .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    })
}

impl Hosting {
    fn scw(&self, args: &[&str]) -> Result<Value> {
        let data = captured(
            Command::new("scw")
                .args(args)
                .arg(format!("region={}", self.region))
                .args(["-o", "json"]),
        )?;
        Ok(serde_json::from_str(&data)?)
    }

    fn update_job(&self, id: &str, image: &str) -> Result<()> {
        self.scw(&[
            "jobs",
            "definition",
            "update",
            id,
            &format!("image-uri={image}"),
        ])?;
        Ok(())
    }

    fn switch(&self, image: &str, privacy: &str) -> Result<()> {
        let service = self.scw(&[
            "container",
            "container",
            "update",
            &self.service,
            &format!("registry-image={image}"),
            &format!("privacy={privacy}"),
            "--wait",
        ])?;
        ensure!(
            service["status"] == "ready",
            "container did not become ready"
        );
        Ok(())
    }
}

const RECEIPTS: &str = "infra/scaleway/contributor-releases";

fn brief_status(image: &str) -> Result<String> {
    let digest = image.split_once('@').context("missing digest")?.1;
    ensure!(valid_digest(digest), "invalid receipt digest");
    let file = format!("{RECEIPTS}/{}.brief", &digest[7..]);
    let expected = fs::read_to_string(&file).with_context(|| format!("Missing expected brief status for {digest}. Restore {file} from the release records before deploying."))?;
    ensure!(
        matches!(expected.as_str(), "200" | "404"),
        "invalid brief receipt"
    );
    Ok(expected)
}

fn verify(brief: &str) -> Result<()> {
    let origin = "https://contribute.eigin.ai";
    for (path, expected) in [
        ("/healthz", "200"),
        ("/", "200"),
        ("/calls/tool-safety", brief),
        ("/review/calls/tool-safety", "404"),
        ("/auth/gitlab", "303"),
    ] {
        let result = captured(Command::new("curl").args([
            "--silent",
            "--show-error",
            "--max-time",
            "45",
            "--output",
            "/dev/null",
            "--write-out",
            "%{response_code} %{redirect_url}",
            &format!("{origin}{path}"),
        ]))?;
        let (status, location) = result.split_once(' ').unwrap_or((&result, ""));
        ensure!(
            status == expected,
            "{path}: expected {expected}, got {status}"
        );
        if path == "/auth/gitlab" {
            ensure!(
                location.starts_with("https://code.eigin.ai/oauth/authorize?"),
                "unexpected OAuth redirect"
            );
        }
    }
    Ok(())
}

/// Confirm the production target before promoting the prepared image.
pub fn run(args: Args) -> Result<()> {
    if matches!(args.action, Action::AfterApply) {
        ensure!(
            std::env::var("EIGIN_DEPLOY_HANDOFF").as_deref() == Ok("production"),
            "after-apply requires the production infra deploy workflow"
        );
    }
    std::env::set_current_dir(crate::config::repo_root()?)?;
    let data = captured(
        Command::new("terraform")
            .args([
                "-chdir=infra/scaleway",
                "output",
                "-json",
                "contributor_release",
            ])
            .env("TF_WORKSPACE", "production"),
    )?;
    let host: Hosting =
        serde_json::from_str(&data).context("missing contributor hosting outputs")?;
    let expected = format!(
        "rg.{}.scw.cloud/eigin-production-contributor/portal",
        host.region
    );
    ensure!(host.repo == expected, "unexpected production registry");
    if let Action::Rollback { digest } = &args.action {
        ensure!(
            valid_digest(digest) && !host.service.is_empty(),
            "rollback requires a provisioned service and a SHA-256 digest"
        );
    }
    let digest = match &args.action {
        Action::AfterApply => &host.digest,
        Action::Rollback { digest } => digest,
    };
    ensure!(valid_digest(digest), "invalid candidate digest");
    let image = format!("{}@{}", host.repo, digest);
    if !matches!(args.action, Action::AfterApply) {
        crate::confirm::confirm(&format!(
            "Deploy {image} to contribute.eigin.ai in production project {}?",
            host.project
        ))?;
    }
    let stamp = SystemTime::now().duration_since(UNIX_EPOCH)?.as_millis();
    let previous = host.scw(&["container", "container", "get", &host.service])?;
    let old = previous["registry_image"]
        .as_str()
        .context("missing previous image")?;
    let privacy = previous["privacy"]
        .as_str()
        .context("missing privacy setting")?;
    ensure!(
        matches!(privacy, "public" | "private")
            && old
                .strip_prefix(&format!("{}@", host.repo))
                .is_some_and(valid_digest),
        "cannot identify a safe rollback target"
    );
    if matches!(args.action, Action::AfterApply)
        && privacy == "public"
        && old == image
        && previous["status"] == "ready"
    {
        println!("Contributor portal already serves {image}.");
        return Ok(());
    }
    // A private first deployment may return 401; only DNS and TLS need to work here.
    captured(Command::new("curl").args([
        "--silent", "--head", "--max-time", "15", "--output", "/dev/null",
        "https://contribute.eigin.ai/healthz",
    ])).context("Cannot reach https://contribute.eigin.ai. Check the CNAME and Scaleway custom-domain TLS binding; no deployment changes made")?;
    if matches!(args.action, Action::Rollback { .. }) {
        ensure!(privacy == "public", "first deployment must run migrations");
    }
    let old_brief = if privacy == "public" {
        Some(brief_status(old)?)
    } else {
        None
    };
    let target_brief = match args.action {
        Action::AfterApply => "200".to_owned(),
        Action::Rollback { .. } => brief_status(&image)?,
    };
    for id in [&host.migrate, &host.prune] {
        let job = host.scw(&["jobs", "definition", "get", id])?;
        ensure!(job["project_id"] == host.project, "unexpected job project");
    }
    if matches!(args.action, Action::AfterApply) {
        host.update_job(&host.migrate, &image)?;
        let run = host.scw(&["jobs", "definition", "start", &host.migrate, "--wait"])?;
        ensure!(
            run["state"] == "succeeded",
            "migration failed; serving revision unchanged"
        );
    }
    if let Err(err) = host
        .switch(&image, "public")
        .and_then(|_| verify(&target_brief))
        .and_then(|_| host.update_job(&host.prune, &image))
    {
        host.switch(old, privacy)
            .context("restore previous service manually; automatic rollback failed")?;
        host.update_job(&host.prune, old)?;
        if let Some(status) = old_brief {
            verify(&status).context("check restored service manually")?;
        }
        bail!("release failed; previous service restored: {err}");
    }
    let dir = RECEIPTS;
    fs::create_dir_all(dir)?;
    fs::write(format!("{dir}/{}.brief", &digest[7..]), target_brief)?;
    fs::write(
        format!("{dir}/{stamp}.json"),
        serde_json::to_vec_pretty(
            &serde_json::json!({"timestamp_ms":stamp as u64,"image":image,"previous":old,"verified":true}),
        )?,
    )?;
    println!("Verified {image} at https://contribute.eigin.ai");
    Ok(())
}
