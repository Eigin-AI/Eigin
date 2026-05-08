use anyhow::{Context, Result};
use std::fs::{self, File};
use std::io::Read;
use std::path::PathBuf;
use std::process::Command;

/// Run a command, capturing all output to a log file.
///
/// Prints a short status line on start, and on completion shows either a
/// success confirmation or a failure summary with the last 30 lines of the
/// log. The full log is always written regardless of outcome.
#[derive(clap::Args)]
pub struct RunArgs {
    /// Path to the log file.
    #[arg(long)]
    pub log: PathBuf,

    /// Label shown in status output.
    #[arg(long)]
    pub label: String,

    /// The command and its arguments.
    #[arg(trailing_var_arg = true, required = true)]
    pub cmd: Vec<String>,
}

pub fn run(args: RunArgs) -> Result<()> {
    if let Some(parent) = args.log.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("creating log directory {}", parent.display()))?;
    }

    println!("→ {}…", args.label);

    let log_file = File::create(&args.log)
        .with_context(|| format!("creating log file {}", args.log.display()))?;

    let status = Command::new(&args.cmd[0])
        .args(&args.cmd[1..])
        .stdout(log_file.try_clone()?)
        .stderr(log_file)
        .status()
        .with_context(|| format!("spawning {:?}", args.cmd[0]))?;

    if status.success() {
        println!(
            "✓ {} succeeded. Full log: {}",
            args.label,
            args.log.display()
        );
        return Ok(());
    }

    println!("✗ {} failed. Full log: {}", args.label, args.log.display());
    println!();

    let tail = read_tail(&args.log, 30)?;
    println!("--- Last 30 lines ---");
    print!("{}", tail);
    println!("--- End of tail ---");

    let code = status.code().unwrap_or(1);
    std::process::exit(code);
}

fn read_tail(path: &PathBuf, n: usize) -> Result<String> {
    let mut file = File::open(path)?;
    let mut content = String::new();
    file.read_to_string(&mut content)?;
    let lines: Vec<&str> = content.lines().collect();
    let start = lines.len().saturating_sub(n);
    Ok(lines[start..].join("\n") + if content.ends_with('\n') { "\n" } else { "" })
}
