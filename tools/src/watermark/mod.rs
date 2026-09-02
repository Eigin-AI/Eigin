use std::fs;
use std::io::{self, Read};

use anyhow::{Context, Result};
use clap::{Args, Subcommand};

mod codec;

/// Inspect Eigin's best-effort text watermark.
#[derive(Args)]
pub struct WatermarkArgs {
    #[command(subcommand)]
    command: WatermarkCommand,
}

#[derive(Subcommand)]
enum WatermarkCommand {
    /// Report whether text carries the Eigin watermark.
    ///
    /// Reads from a file, or from stdin when the path is "-".
    /// Exit codes: 0 = watermarked, 1 = not watermarked, 2 = read error.
    Detect(DetectArgs),
}

#[derive(Args)]
pub struct DetectArgs {
    /// Path to a text file, or "-" to read stdin.
    input: String,
}

pub fn run(args: WatermarkArgs) -> Result<()> {
    match args.command {
        WatermarkCommand::Detect(args) => detect(args),
    }
}

fn detect(args: DetectArgs) -> Result<()> {
    // Read errors exit 2, distinct from the yes/no detection result.
    let text = match read_input(&args.input) {
        Ok(text) => text,
        Err(err) => {
            eprintln!("error: {err:#}");
            std::process::exit(2);
        }
    };
    let result = codec::detect(&text);

    if result.watermarked {
        println!(
            "watermarked: yes (version {}, {} marker(s))",
            result.version, result.count
        );
        std::process::exit(0);
    } else {
        println!("watermarked: no");
        std::process::exit(1);
    }
}

fn read_input(path: &str) -> Result<String> {
    if path == "-" {
        let mut buf = String::new();
        io::stdin()
            .read_to_string(&mut buf)
            .context("failed to read stdin")?;
        Ok(buf)
    } else {
        fs::read_to_string(path).with_context(|| format!("failed to read {path}"))
    }
}
