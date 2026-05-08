use std::fs;
use std::process::Command;
use tempfile::TempDir;

fn eigin_tools() -> Command {
    Command::new(env!("CARGO_BIN_EXE_eigin-tools"))
}

fn run_commit_msg(message: &str) -> std::process::Output {
    let dir = TempDir::new().unwrap();
    let file = dir.path().join("COMMIT_EDITMSG");
    fs::write(&file, message).unwrap();
    eigin_tools()
        .args(["hooks", "commit-msg", file.to_str().unwrap()])
        .output()
        .unwrap()
}

#[test]
fn accepts_valid_feat() {
    let out = run_commit_msg("feat(chat): add dictation stream view\n");
    assert!(out.status.success());
}

#[test]
fn accepts_valid_fix_no_scope() {
    let out = run_commit_msg("fix: correct relay timeout\n");
    assert!(out.status.success());
}

#[test]
fn accepts_breaking_change_marker() {
    let out = run_commit_msg("feat(api)!: remove deprecated endpoint\n");
    assert!(out.status.success());
}

#[test]
fn rejects_unknown_type() {
    let out = run_commit_msg("update: something\n");
    assert!(!out.status.success());
}

#[test]
fn rejects_missing_description() {
    let out = run_commit_msg("feat(chat):\n");
    assert!(!out.status.success());
}

#[test]
fn rejects_empty_message() {
    let out = run_commit_msg("# just a comment\n");
    assert!(!out.status.success());
}

#[test]
fn skips_comment_lines() {
    let out = run_commit_msg("# this is a comment\nfeat: real message\n");
    assert!(out.status.success());
}

#[test]
fn accepts_all_valid_types() {
    for t in &[
        "build", "chore", "ci", "docs", "feat", "fix", "perf", "refactor", "revert", "style",
        "test",
    ] {
        let msg = format!("{t}: do something\n");
        let out = run_commit_msg(&msg);
        assert!(out.status.success(), "type '{t}' should be accepted");
    }
}
