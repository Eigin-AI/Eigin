pub mod ios;

use anyhow::Result;
use clap::Subcommand;

pub mod generate;
pub mod validate;

/// Localization codegen and validation.
///
/// Generates and validates platform-specific localization source files
/// from the shared Localizable.xcstrings catalog.
#[derive(clap::Args)]
pub struct Args {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Generate localization source files from catalog.
    Generate(generate::GenerateArgs),
    /// Validate that all String(localized:) keys exist in the generated output.
    Validate(validate::ValidateArgs),
}

pub fn run(args: Args) -> Result<()> {
    match args.command {
        Command::Generate(args) => generate::run(args),
        Command::Validate(args) => validate::run(args),
    }
}

/// Generate localization for all configured platforms. Called by `eigin-tools generate`.
pub fn generate_all(repo_root: &str) -> Result<()> {
    generate::run_with_root(generate::GenerateArgs { platform: None }, repo_root)
}

/// Validate localization for all configured platforms. Called by `eigin-tools lint`.
pub fn validate_all(repo_root: &str) -> Result<bool> {
    validate::run_with_root(validate::ValidateArgs { platform: None }, repo_root)
}
