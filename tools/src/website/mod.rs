//! Local operator publishing of the static website.
mod assets;
mod publish;
mod verify;

use anyhow::{Context, Result, bail, ensure};
use std::{
    env, fs,
    io::{self, Write},
    path::{Path, PathBuf},
    process::{Command, Stdio},
};

/// Generate branding assets, publish or verify the website.
#[derive(clap::Args)]
pub struct Args {
    #[command(subcommand)]
    command: Action,
}

#[derive(clap::Subcommand, Clone, Copy, PartialEq)]
enum Action {
    /// Regenerate favicon and social images from the brand sources and installed fonts.
    Assets,
    /// Build and publish using production Terraform outputs; never apply infrastructure.
    Release,
    /// Check the deployed routes and assets from the current local build.
    Verify,
}

/// Run the website workflow from the repository root.
pub fn run(args: Args) -> Result<()> {
    let root = PathBuf::from(crate::config::repo_root()?);
    if args.command == Action::Assets {
        return assets::generate(&root);
    }
    let build = root.join("src/eigin_website/build");
    let infra = root.join("infra/scaleway");
    if args.command == Action::Verify {
        preflight(&root, &["curl"])?;
        return verify::run(&root, &build, &required("WEBSITE_URL")?);
    }
    preflight(&root, &["just", "npm", "aws", "curl", "tar", "terraform"])?;
    let dir = format!("-chdir={}", infra.display());
    let terraform = |arguments: &[&str], capture| {
        execute(
            Command::new("terraform")
                .current_dir(&root)
                .arg(&dir)
                .args(arguments)
                .env("TF_WORKSPACE", "production"),
            capture,
        )
    };
    terraform(&["init", "-input=false"], false)?;
    let output = |key| {
        terraform(&["output", "-raw", key], true)
        .with_context(|| "Website hosting is not ready. Run just infra init production and just infra deploy production as an authorized operator first.")
    };
    let target = publish::Target::new(
        output("website_bucket_name")?,
        output("website_s3_endpoint")?,
        output("website_preview_url")?,
    )?;
    let credentials = publish::Credentials {
        access_key: output("website_upload_access_key")?,
        secret_key: output("website_upload_secret_key")?,
    };
    ensure!(
        !credentials.access_key.is_empty() && !credentials.secret_key.is_empty(),
        "Missing website publisher credentials in production state"
    );
    let archive = build_site(&root, &build, &infra)?;
    confirm(&format!(
        "Publish to {} at {} using the website publisher? Check {}.",
        target.bucket, target.endpoint, target.url
    ))?;
    publish::run(&root, &build, &target, &credentials)?;
    verify::run(&root, &build, &target.url)?;
    let receipt = archive.with_extension("verified.json");
    fs::write(
        &receipt,
        serde_json::to_vec_pretty(&serde_json::json!({
            "archive": archive.file_name().context("archive filename")?.to_string_lossy(),
            "url": target.url,
            "verified_at_unix_seconds": std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)?.as_secs(),
            "checks": "automated smoke tests; browser acceptance remains an operator step"
        }))?,
    )?;
    println!("Verified archive receipt: {}", receipt.display());
    println!(
        "Published and smoke-tested. Complete browser/domain checks in infra/scaleway/modules/website/README.md."
    );
    Ok(())
}

fn required(name: &str) -> Result<String> {
    let value = env::var(name).with_context(|| format!("Set {name}"))?;
    ensure!(!value.trim().is_empty(), "Set {name}");
    Ok(value)
}

fn preflight(root: &Path, tools: &[&str]) -> Result<()> {
    for tool in tools {
        command(root, "which", &[tool], true)
            .with_context(|| format!("Install required tool: {tool}"))?;
    }
    Ok(())
}

fn confirm(message: &str) -> Result<()> {
    print!("{message} Type yes to continue: ");
    io::stdout().flush()?;
    let mut response = String::new();
    io::stdin().read_line(&mut response)?;
    ensure!(response.trim() == "yes", "Cancelled");
    Ok(())
}

fn command(root: &Path, program: &str, args: &[&str], capture: bool) -> Result<String> {
    execute(Command::new(program).args(args).current_dir(root), capture)
}

fn execute(command: &mut Command, capture: bool) -> Result<String> {
    let program = command.get_program().to_string_lossy().into_owned();
    if capture {
        let output = command
            .stderr(Stdio::inherit())
            .output()
            .with_context(|| format!("running {program}"))?;
        ensure!(
            output.status.success(),
            "{program} failed: {}",
            output.status
        );
        Ok(String::from_utf8(output.stdout)?.trim().to_string())
    } else {
        let status = command
            .status()
            .with_context(|| format!("running {program}"))?;
        if !status.success() {
            bail!("{program} failed: {status}");
        }
        Ok(String::new())
    }
}

fn build_site(root: &Path, build: &Path, infra: &Path) -> Result<PathBuf> {
    command(root, "just", &["generate", "web"], false)?;
    command(
        root,
        "npm",
        &["run", "check", "--workspace", "@eigin/website"],
        false,
    )?;
    command(
        root,
        "npm",
        &["run", "build", "--workspace", "@eigin/website"],
        false,
    )?;
    ensure!(
        build.join("index.html").is_file(),
        "Build has no index.html"
    );
    prepare_pages(build)?;
    let releases = infra.join("website-releases");
    fs::create_dir_all(&releases)?;
    let archive = releases.join(format!("{}.tar.gz", uuid::Uuid::new_v4()));
    command(
        root,
        "tar",
        &[
            "-czf",
            &archive.to_string_lossy(),
            "-C",
            &build.to_string_lossy(),
            ".",
        ],
        false,
    )?;
    println!("Recovery artifact: {}", archive.display());
    Ok(archive)
}

fn prepare_pages(build: &Path) -> Result<()> {
    for slug in ["privacy", "terms", "contact", "support"] {
        ensure!(
            build.join(format!("en/{slug}/index.html")).is_file(),
            "Missing compatibility destination: /en/{slug}/"
        );
        let dir = build.join(slug);
        fs::create_dir_all(&dir)?;
        fs::write(
            dir.join("index.html"),
            format!(
                "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\"><title>Eigin {slug}</title>\
             <meta http-equiv=\"refresh\" content=\"0;url=/en/{slug}/\">\
             <link rel=\"canonical\" href=\"/en/{slug}/\"><a href=\"/en/{slug}/\">Continue to {slug}</a></html>\n"
            ),
        )?;
    }
    fs::write(
        build.join("404.html"),
        "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\"><title>Page not found</title><h1>Page not found</h1><a href=\"/\">Eigin home</a></html>\n",
    )?;
    Ok(())
}
