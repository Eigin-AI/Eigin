use anyhow::{Context, Result};
use clap::Subcommand;
use std::fs;
use std::path::Path;
use std::process::Command;

pub mod model;
pub mod render;
pub mod resolve;

#[cfg(test)]
pub mod test_support;

pub use model::{Config, Env, LocalizeConfig};

/// Read, resolve and render the project's configuration.
#[derive(clap::Args)]
pub struct Args {
    #[command(subcommand)]
    command: ConfigCommand,
}

#[derive(Subcommand)]
enum ConfigCommand {
    /// Create a starter .env from .env.example. Never overwrites an existing one.
    Init(InitArgs),
    /// Print shell exports for a consumer.
    ///
    /// Capture before eval so a missing secret fails the recipe:
    ///   vars="$(eigin-tools config export tf-vars staging)"; eval "$vars"
    Export(ExportArgs),
    /// Print a single resolved secret, empty when unset.
    Secret(SecretArgs),
    /// Report any missing configuration or secrets.
    Check,
}

#[derive(clap::Args)]
pub struct ExportArgs {
    /// Which consumer to render for.
    target: Target,
    /// Environment. Required for relay and tf-vars; ios renders both.
    env: Option<Env>,
}

#[derive(Clone, Copy, clap::ValueEnum)]
enum Target {
    /// xcodegen and fastlane.
    Ios,
    /// A locally run relay.
    Relay,
    /// Terraform.
    TfVars,
}

#[derive(clap::Args)]
pub struct InitArgs {
    /// Overwrite an existing .env.
    #[arg(long)]
    force: bool,
}

#[derive(clap::Args)]
pub struct SecretArgs {
    /// Unsuffixed secret name, e.g. TOKEN_ENCRYPTION_SECONDARY_KEY.
    name: String,
    env: Env,
}

pub fn run(args: Args) -> Result<()> {
    let root = repo_root()?;

    // Init runs before anything is resolved: there may be no .env yet.
    if let ConfigCommand::Init(args) = &args.command {
        return init(&root, args.force);
    }

    let resolved = resolve::resolve(&root)?;

    match args.command {
        ConfigCommand::Init(_) => unreachable!("handled above"),
        ConfigCommand::Export(args) => {
            let rendered = match args.target {
                Target::Ios => render::ios::render(&resolved),
                Target::Relay => render::relay::render(&resolved, require_env(args.env)?, &root)?,
                Target::TfVars => render::tf_vars::render(&resolved, require_env(args.env)?)?,
            };
            // stdout is eval'd by the caller, so warnings must go to stderr.
            for warning in &rendered.warnings {
                eprintln!("warning: {warning}");
            }
            print!("{}", rendered.exports);
        }
        ConfigCommand::Secret(args) => {
            println!("{}", resolved.secrets.optional_env(&args.name, args.env));
        }
        ConfigCommand::Check => check(&resolved, &root)?,
    }
    Ok(())
}

fn require_env(env: Option<Env>) -> Result<Env> {
    env.context("this target needs an environment: staging or production")
}

/// Seed a `.env` from `.env.example`.
///
/// The template's `YOUR_*` placeholders are recognised as unset everywhere else,
/// so a freshly seeded file reports honestly instead of satisfying every check.
pub fn init(repo_root: &str, force: bool) -> Result<()> {
    let target = format!("{repo_root}/.env");
    let template = format!("{repo_root}/.env.example");

    if Path::new(&target).exists() && !force {
        println!("{target} already exists — leaving it alone (use --force to replace).");
        return Ok(());
    }

    let contents = fs::read_to_string(&template).with_context(|| format!("reading {template}"))?;
    fs::write(&target, contents).with_context(|| format!("writing {target}"))?;

    println!("Created .env from .env.example.");
    println!(
        "Placeholders count as unset, so you can build now and fill values in as you need them."
    );
    println!("Run `just config` to see what's ready.");
    Ok(())
}

/// Report what the current configuration lets you do.
///
/// Contributors can't obtain the relay or infra secrets, so absence is reported
/// as a scoped limit rather than a failure.
fn check(resolved: &resolve::Resolved, repo_root: &str) -> Result<()> {
    // Infallible by construction: an iOS build is never blocked by configuration.
    let ios = render::ios::render(resolved);
    if ios.warnings.is_empty() {
        println!("iOS app      ready — build with `just build ios staging`");
    } else {
        println!("iOS app      builds, with limits:");
        for warning in &ios.warnings {
            println!("               - {warning}");
        }
    }

    let relay_failures: Vec<String> = Env::ALL
        .into_iter()
        .filter_map(|env| {
            render::relay::render(resolved, env, repo_root)
                .err()
                .map(|e| format!("{}: {e}", env.as_str()))
        })
        .collect();
    if relay_failures.is_empty() {
        println!("Local relay  ready — run with `just run relay`");
    } else {
        println!(
            "Local relay  unavailable ({}) — expected unless you maintain the relay",
            relay_failures.join("; ")
        );
    }

    let infra_ready = render::tf_vars::credentials_ready(resolved);
    if infra_ready {
        println!("Infra        credentials present");
    } else {
        println!("Infra        unavailable — expected unless you deploy Eigin");
    }

    if !ios.warnings.is_empty() || !infra_ready {
        println!("\nYou can build. Missing pieces above only affect the features they name.");
    }
    Ok(())
}

/// Load everything committed under `config/`.
pub fn load(repo_root: &str) -> Result<Config> {
    Ok(Config {
        app: read_toml(&format!("{repo_root}/config/app.toml"))?,
        tools: read_toml(&format!("{repo_root}/config/tools.toml"))?,
    })
}

fn read_toml<T: serde::de::DeserializeOwned>(path: &str) -> Result<T> {
    let content = fs::read_to_string(path).with_context(|| format!("reading {path}"))?;
    toml::from_str(&content).with_context(|| format!("parsing {path}"))
}

pub fn repo_root() -> Result<String> {
    let out = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .context("running git rev-parse --show-toplevel")?;
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}
