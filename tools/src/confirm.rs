use anyhow::{Result, ensure};
use std::io::{self, Write};

/// Require the operator to type `yes` before changing production.
pub(crate) fn confirm(message: &str) -> Result<()> {
    print!("{message} Type yes to continue: ");
    io::stdout().flush()?;
    let mut response = String::new();
    io::stdin().read_line(&mut response)?;
    ensure!(response.trim() == "yes", "Cancelled");
    Ok(())
}
