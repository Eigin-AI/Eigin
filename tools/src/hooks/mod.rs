use anyhow::Result;
use clap::Subcommand;

mod commit_msg;
mod install;
mod pre_commit;

#[derive(clap::Args)]
/// Manage and run git hooks.
///
/// Use `install` to write hooks into .git/hooks/. The installed hooks
/// call back into this binary for pre-commit and commit-msg validation.
pub struct Args {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Install git hooks into .git/hooks/.
    Install,
    /// Run the pre-commit hook.
    PreCommit,
    /// Run the commit-msg hook.
    CommitMsg(commit_msg::CommitMsgArgs),
}

pub fn run(args: Args) -> Result<()> {
    match args.command {
        Command::Install => install::run(),
        Command::PreCommit => pre_commit::run(),
        Command::CommitMsg(args) => commit_msg::run(args),
    }
}
