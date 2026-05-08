use std::fs;
use std::process::Command;
use tempfile::TempDir;

fn eigin_tools() -> Command {
    Command::new(env!("CARGO_BIN_EXE_eigin-tools"))
}

#[test]
fn run_success_exits_zero() {
    let dir = TempDir::new().unwrap();
    let log = dir.path().join("out.log");

    let status = eigin_tools()
        .args([
            "run",
            "--log",
            log.to_str().unwrap(),
            "--label",
            "test",
            "--",
            "true",
        ])
        .status()
        .unwrap();

    assert!(status.success());
    assert!(log.exists());
}

#[test]
fn run_failure_propagates_exit_code() {
    let dir = TempDir::new().unwrap();
    let log = dir.path().join("out.log");

    let status = eigin_tools()
        .args([
            "run",
            "--log",
            log.to_str().unwrap(),
            "--label",
            "test",
            "--",
            "sh",
            "-c",
            "exit 7",
        ])
        .status()
        .unwrap();

    assert_eq!(status.code(), Some(7));
}

#[test]
fn run_captures_output_to_log() {
    let dir = TempDir::new().unwrap();
    let log = dir.path().join("out.log");

    eigin_tools()
        .args([
            "run",
            "--log",
            log.to_str().unwrap(),
            "--label",
            "test",
            "--",
            "sh",
            "-c",
            "echo hello",
        ])
        .status()
        .unwrap();

    let contents = fs::read_to_string(&log).unwrap();
    assert!(contents.contains("hello"));
}

#[test]
fn run_creates_log_directory() {
    let dir = TempDir::new().unwrap();
    let log = dir.path().join("nested/dir/out.log");

    let status = eigin_tools()
        .args([
            "run",
            "--log",
            log.to_str().unwrap(),
            "--label",
            "test",
            "--",
            "true",
        ])
        .status()
        .unwrap();

    assert!(status.success());
    assert!(log.exists());
}
