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
pub struct ExecArgs {
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

pub fn run(args: ExecArgs) -> Result<()> {
    let mut command = Command::new(&args.cmd[0]);
    command.args(&args.cmd[1..]);
    logged(&args.label, &args.log, &mut command)
}

/// Run a prepared command with its output captured, for callers that build one
/// themselves rather than passing it on a command line.
pub fn logged(label: &str, log: &PathBuf, command: &mut Command) -> Result<()> {
    if let Some(parent) = log.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("creating log directory {}", parent.display()))?;
    }

    println!("→ {label}…");

    let log_file =
        File::create(log).with_context(|| format!("creating log file {}", log.display()))?;

    let status = command
        .stdout(log_file.try_clone()?)
        .stderr(log_file)
        .status()
        .with_context(|| format!("spawning {:?}", command.get_program()))?;

    if status.success() {
        println!("✓ {label} succeeded. Full log: {}", log.display());
        return Ok(());
    }

    println!("✗ {label} failed. Full log: {}", log.display());
    println!();

    let tail = read_tail(log, 30)?;
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
