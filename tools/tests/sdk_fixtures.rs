//! Exercise host selection through the CLI with process boundaries replaced.

use std::{fs, os::unix::fs::PermissionsExt, process::Command};
use tempfile::TempDir;

#[path = "support/version.rs"]
mod version_support;

fn executable(path: &std::path::Path, script: &str) {
    fs::write(path, script).unwrap();
    fs::set_permissions(path, fs::Permissions::from_mode(0o755)).unwrap();
}

#[test]
fn browser_fixture_check_does_not_invoke_native_compilers() {
    let directory = TempDir::new().unwrap();
    let root = directory.path();
    let bin = root.join("bin");
    fs::create_dir_all(&bin).unwrap();
    fs::create_dir_all(root.join("node_modules/.bin")).unwrap();
    fs::create_dir_all(root.join("src/eigin_sdk/web")).unwrap();
    executable(&bin.join("git"), "#!/bin/sh\nprintf '%s' \"$TEST_ROOT\"\n");
    executable(
        &root.join("node_modules/.bin/ubrn"),
        "#!/bin/sh\n[ -z \"${RUSTUP_TOOLCHAIN:-}\" ] || exit 42\nprintf 'browser fixture generated\\n' >> \"$TEST_LOG\"\n",
    );
    for name in ["cargo", "swiftc", "xcodebuild"] {
        executable(
            &bin.join(name),
            "#!/bin/sh\nprintf 'unexpected Apple/native tooling\\n' >> \"$TEST_LOG\"\nexit 99\n",
        );
    }
    fs::write(root.join("node_modules/.bin/vite"), "installed").unwrap();
    let log = root.join("commands.log");
    let output = Command::new(env!("CARGO_BIN_EXE_eigin-tools"))
        .args(["check-sdk-bindings", "web"])
        .current_dir(root)
        .env("PATH", &bin)
        .env("TEST_ROOT", root)
        .env("TEST_LOG", &log)
        .env("RUSTUP_TOOLCHAIN", "unrelated-toolchain")
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        fs::read_to_string(log).unwrap(),
        "browser fixture generated\n"
    );
}

#[test]
fn sdk_web_generation_restores_missing_npm_tooling() {
    let directory = version_support::fixture();
    let root = directory.path();
    let bin = root.join("bin");
    fs::create_dir_all(&bin).unwrap();
    fs::create_dir_all(root.join("src/eigin_sdk/web")).unwrap();
    executable(&bin.join("git"), "#!/bin/sh\nprintf '%s' \"$TEST_ROOT\"\n");
    executable(
        &bin.join("npm"),
        r#"#!/bin/sh
set -eu
[ "$1" = ci ]
printf 'npm ci\n' >> "$TEST_LOG"
mkdir -p "$TEST_ROOT/node_modules/.bin"
cat > "$TEST_ROOT/node_modules/.bin/ubrn" <<'GENERATOR'
#!/bin/sh
set -eu
[ -z "${RUSTUP_TOOLCHAIN:-}" ] || exit 42
mkdir -p "$TEST_ROOT/src/eigin_sdk/target/web-bindings"
printf 'generated binding' > "$TEST_ROOT/src/eigin_sdk/target/web-bindings/api.ts"
GENERATOR
chmod +x "$TEST_ROOT/node_modules/.bin/ubrn"
touch "$TEST_ROOT/node_modules/.bin/vite"
"#,
    );
    let log = root.join("commands.log");
    for _ in 0..2 {
        let output = Command::new(env!("CARGO_BIN_EXE_eigin-tools"))
            .args(["generate", "sdk", "web"])
            .current_dir(root)
            .env("PATH", format!("{}:/usr/bin:/bin", bin.display()))
            .env("TEST_ROOT", root)
            .env("TEST_LOG", &log)
            .env("RUSTUP_TOOLCHAIN", "unrelated-toolchain")
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
    }
    assert_eq!(fs::read_to_string(log).unwrap(), "npm ci\n");
    assert_eq!(
        fs::read_to_string(root.join("src/eigin_sdk/web/src/generated/api.ts")).unwrap(),
        "generated binding"
    );
}
