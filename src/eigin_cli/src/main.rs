mod inference;

use clap::{Parser, Subcommand};
use std::process::ExitCode;

#[derive(Parser)]
#[command(name = "eigin", about = "Eigin headless SDK host", version)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Initialize the SDK without platform services.
    Init,
    /// Print bundled SDK third-party license and copyright notices.
    Notices,
    /// Discover models and run inference without an agent.
    Inference {
        #[command(subcommand)]
        command: inference::Command,
    },
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("{error}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> Result<(), Box<dyn std::error::Error>> {
    match Cli::parse().command {
        Command::Notices => print!("{}", eigin_sdk::THIRD_PARTY_NOTICES),
        Command::Init => {
            futures::executor::block_on(eigin_sdk::initialize())?;
            println!("Eigin SDK initialized");
        }
        Command::Inference { command } => inference::run(command)?,
    }
    Ok(())
}
