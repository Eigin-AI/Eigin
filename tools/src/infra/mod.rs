use anyhow::Result;
use clap::Subcommand;

pub mod tf_vars;

#[derive(clap::Args)]
pub struct Args {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Print Terraform TF_VAR_* exports for the given environment.
    ///
    /// Usage in shell: eval "$(eigin-tools infra tf-vars staging)"
    TfVars(tf_vars::TfVarsArgs),
}

pub fn run(args: Args) -> Result<()> {
    match args.command {
        Command::TfVars(args) => tf_vars::run(args),
    }
}
