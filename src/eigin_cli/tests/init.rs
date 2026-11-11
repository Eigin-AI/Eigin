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

#[test]
fn prints_bundled_sdk_notices_without_initializing() {
    let output = Command::new(env!("CARGO_BIN_EXE_eigin"))
        .arg("notices")
        .output()
        .unwrap();
    assert!(output.status.success());
    assert_eq!(output.stdout, eigin_sdk::THIRD_PARTY_NOTICES.as_bytes());
    assert!(output.stderr.is_empty());
}
