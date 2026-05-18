use anyhow::Result;
use clap::{Parser, Subcommand};

mod codegen;
mod config;
mod design;
mod format;
mod generate;
mod hooks;
mod infra;
mod lint;
mod localize;
mod run;

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
    /// Format all code in the repo.
    Format(format::FormatArgs),
    /// Manage and run git hooks.
    Hooks(hooks::Args),
    /// Infrastructure tooling (Terraform, deployment).
    Infra(infra::Args),
    /// Lint all code in the repo without modifying files.
    Lint(lint::LintArgs),
    /// Localization codegen and validation.
    Localize(localize::Args),
    /// Run a command, capturing output to a log file.
    Run(run::RunArgs),
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Command::Generate(args) => generate::run(args),
        Command::Format(args) => format::run(args),
        Command::Hooks(args) => hooks::run(args),
        Command::Infra(args) => infra::run(args),
        Command::Lint(args) => lint::run(args),
        Command::Localize(args) => localize::run(args),
        Command::Run(args) => run::run(args),
    }
}
