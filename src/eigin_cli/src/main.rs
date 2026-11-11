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
}

fn main() -> ExitCode {
    let result = match Cli::parse().command {
        Command::Notices => {
            print!("{}", eigin_sdk::THIRD_PARTY_NOTICES);
            return ExitCode::SUCCESS;
        }
        Command::Init => futures::executor::block_on(eigin_sdk::initialize()),
    };
    match result {
        Ok(()) => {
            println!("Eigin SDK initialized");
            ExitCode::SUCCESS
        }
        Err(error) => {
            eprintln!("{error}");
            ExitCode::FAILURE
        }
    }
}
