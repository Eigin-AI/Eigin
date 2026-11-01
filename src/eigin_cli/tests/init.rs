use std::process::Command;

#[test]
fn initializes_without_platform_services() {
    let output = Command::new(env!("CARGO_BIN_EXE_eigin"))
        .arg("init")
        .output()
        .unwrap();
    assert!(output.status.success());
    assert_eq!(
        String::from_utf8(output.stdout).unwrap(),
        "Eigin SDK initialized\n"
    );
    assert!(output.stderr.is_empty());
}

#[test]
fn rejects_unknown_commands() {
    let output = Command::new(env!("CARGO_BIN_EXE_eigin"))
        .arg("unknown")
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(2));
}
