use anyhow::{Context, Result};
use regex::Regex;
use std::fs;
use std::process::Command;

#[derive(clap::Args)]
/// Validate that a commit message follows Conventional Commits format.
///
/// Reads the commit message file written by git, strips comment lines,
/// and checks the header against the Conventional Commits pattern:
///   <type>(<scope>): <description>
///
/// Valid types: build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test
pub struct CommitMsgArgs {
    /// Path to the commit message file (provided by git).
    pub file: String,
}

pub fn run(args: CommitMsgArgs) -> Result<()> {
    let content = fs::read_to_string(&args.file)
        .with_context(|| format!("reading commit message file {}", args.file))?;

    let comment_char = git_comment_char().unwrap_or('#');

    let header = content
        .lines()
        .filter(|l| !l.starts_with(comment_char))
        .find(|l| !l.is_empty());

    let Some(header) = header else {
        print_error("commit message is empty", None);
        std::process::exit(1);
    };

    // Merge commits carry git's auto-generated "Merge ..." header, which isn't
    // Conventional Commits and shouldn't be forced into it — skip validation.
    if header.starts_with("Merge ") {
        return Ok(());
    }

    let pattern = Regex::new(
        r"^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)(\([[:alnum:]._-]+\))?(!)?: [[:alnum:]]",
    )
    .unwrap();

    if !pattern.is_match(header) {
        print_error(
            "header does not match Conventional Commits format",
            Some(header),
        );
        std::process::exit(1);
    }

    Ok(())
}

fn print_error(msg: &str, got: Option<&str>) {
    eprintln!("error: commit-msg hook: {msg}");
    eprintln!();
    if let Some(header) = got {
        eprintln!("  Got:      {header}");
        eprintln!("  Expected: <type>(<scope>): <description>");
        eprintln!();
    }
    eprintln!("  types: build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test");
    eprintln!("  example: feat(chat): add dictation stream view");
}

fn git_comment_char() -> Option<char> {
    let out = Command::new("git")
        .args(["config", "core.commentChar"])
        .output()
        .ok()?;
    String::from_utf8_lossy(&out.stdout).trim().chars().next()
}
