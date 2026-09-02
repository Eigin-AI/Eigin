use anyhow::Result;
use clap::{Parser, Subcommand};

mod assets;
mod codegen;
mod config;
mod design;
mod format;
mod generate;
mod grant;
mod hooks;
mod knowledge;
mod lint;
mod localize;
mod prompts;
mod run;
mod security;
mod watermark;

#[derive(Parser)]
#[command(name = "eigin-tools")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Run all code generation tasks for the project.
    Generate(generate::GenerateArgs),
    /// Manage and upload self-hosted model assets.
    Assets(assets::AssetsArgs),
    /// Format all code in the repo.
    Format(format::FormatArgs),
    /// Generate and sign credit grant tokens.
    Grant(grant::GrantArgs),
    /// Read, resolve and render project configuration.
    Config(config::Args),
    /// Manage and run git hooks.
    Hooks(hooks::Args),
    /// Lint all code in the repo without modifying files.
    Lint(lint::LintArgs),
    /// Localization codegen and validation.
    Localize(localize::Args),
    /// Run a command, capturing output to a log file.
    Run(run::RunArgs),
    /// Scan dependencies and the Relay image for known vulnerabilities.
    Security(security::SecurityArgs),
    /// Inspect Eigin's best-effort text watermark.
    Watermark(watermark::WatermarkArgs),
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Command::Generate(args) => generate::run(args),
        Command::Assets(args) => assets::run(args),
        Command::Format(args) => format::run(args),
        Command::Grant(args) => grant::run(args),
        Command::Config(args) => config::run(args),
        Command::Hooks(args) => hooks::run(args),
        Command::Lint(args) => lint::run(args),
        Command::Localize(args) => localize::run(args),
        Command::Run(args) => run::run(args),
        Command::Security(args) => security::run(args),
        Command::Watermark(args) => watermark::run(args),
    }
}
