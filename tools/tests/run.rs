#![cfg(unix)]

use std::{fs, os::unix::fs::PermissionsExt, path::Path, process::Command};
use tempfile::TempDir;

#[test]
fn just_run_cli_forwards_flags_and_preserves_argument_boundaries() {
    let dir = TempDir::new().unwrap();
    let cargo = dir.path().join("cargo");
    fs::write(&cargo, "#!/bin/sh\nprintf '<%s>\\n' \"$@\"\n").unwrap();
    fs::set_permissions(&cargo, fs::Permissions::from_mode(0o755)).unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap();
    for args in [
        vec![
            "inference",
            "models",
            "--base-url",
            "https://api.berget.ai/v1",
        ],
        vec![
            "inference",
            "chat",
            "--base-url",
            "http://localhost/v1",
            "--model",
            "canned-text",
            "--prompt",
            "What's this? $(echo unsafe)",
            "--api-key-env",
            "",
        ],
        vec!["--help"],
    ] {
        let output = Command::new("just")
            .current_dir(root)
            .env(
                "PATH",
                format!(
                    "{}:{}",
                    dir.path().display(),
                    std::env::var("PATH").unwrap()
                ),
            )
            .args([
                "--set",
                "tools",
                env!("CARGO_BIN_EXE_eigin-tools"),
                "run",
                "cli",
            ])
            .args(&args)
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        let forwarded = String::from_utf8(output.stdout).unwrap();
        let expected: String = args.iter().map(|arg| format!("<{arg}>\n")).collect();
        assert!(
            forwarded.ends_with(&format!("<-->\n{expected}")),
            "{forwarded}"
        );
    }
}
