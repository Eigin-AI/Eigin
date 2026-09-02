use anyhow::Result;
use clap::{Parser, Subcommand};

mod assets;
mod codegen;
mod config;
mod design;
mod dev;
mod exec;
mod format;
mod generate;
mod grant;
mod hooks;
mod knowledge;
mod lint;
mod localize;
mod prompts;
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
    /// Start a target: the relay, or the iOS app on a simulator or a device.
    Run(dev::RunArgs),
    /// Stop a detached target.
    Stop(dev::StopArgs),
    /// Show a target's logs.
    Logs(dev::LogsArgs),
    /// Run a command, capturing output to a log file.
    Exec(exec::ExecArgs),
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
        Command::Run(args) => dev::run(args),
        Command::Stop(args) => dev::stop(args),
        Command::Logs(args) => dev::logs(args),
        Command::Exec(args) => exec::run(args),
        Command::Security(args) => security::run(args),
        Command::Watermark(args) => watermark::run(args),
    }
}
