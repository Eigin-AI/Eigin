//! SDK entry points configure C tooling at the subprocess boundary.

use std::{fs, path::Path, process::Command};
use tempfile::TempDir;

#[path = "support/wasm_toolchain.rs"]
mod wasm_toolchain;
use wasm_toolchain::{clear_overrides, executable, install};

fn fixture() -> TempDir {
    let directory = TempDir::new().unwrap();
    let root = directory.path();
    fs::create_dir_all(root.join("bin")).unwrap();
    fs::create_dir_all(root.join("node_modules/.bin")).unwrap();
    fs::create_dir_all(root.join("src/eigin_sdk/web")).unwrap();
    executable(
        &root.join("bin/git"),
        "#!/bin/sh\nprintf '%s' \"$TEST_ROOT\"\n",
    );
    executable(
        &root.join("node_modules/.bin/ubrn"),
        "#!/bin/sh\nprintf '%s|%s' \"$CC_wasm32_unknown_unknown\" \"$AR_wasm32_unknown_unknown\" > \"$TEST_LOG\"\n",
    );
    fs::write(root.join("node_modules/.bin/vite"), "installed").unwrap();
    directory
}

fn command(root: &Path) -> Command {
    let mut command = Command::new(env!("CARGO_BIN_EXE_eigin-tools"));
    clear_overrides(&mut command);
    command
        .current_dir(root)
        .env("PATH", root.join("bin"))
        .env("TEST_ROOT", root)
        .env("TEST_LOG", root.join("commands.log"))
        .env("UBRN_WASM_BINDGEN", root.join("bin/wasm-bindgen"));
    command
}

#[test]
fn browser_fixtures_discover_tools_and_preserve_explicit_overrides() {
    let directory = fixture();
    let root = directory.path();
    install(&root.join("bin"));
    let output = command(root)
        .args(["check-sdk-bindings", "web"])
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        fs::read_to_string(root.join("commands.log")).unwrap(),
        "clang|llvm-ar"
    );

    let selected = root.join("selected");
    install(&selected);
    let output = command(root)
        .args(["check-sdk-bindings", "web"])
        .env("CC_wasm32_unknown_unknown", selected.join("clang"))
        .env("AR_wasm32_unknown_unknown", selected.join("llvm-ar"))
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        fs::read_to_string(root.join("commands.log")).unwrap(),
        format!(
            "{}|{}",
            selected.join("clang").display(),
            selected.join("llvm-ar").display()
        )
    );
}

#[test]
fn missing_tools_fail_before_running_the_generator() {
    let directory = fixture();
    let root = directory.path();
    for missing in ["clang", "llvm-ar"] {
        install(&root.join("bin"));
        fs::remove_file(root.join("bin").join(missing)).unwrap();
        let output = command(root)
            .args(["check-sdk-bindings", "web"])
            .output()
            .unwrap();
        assert!(!output.status.success());
        let error = String::from_utf8_lossy(&output.stderr);
        assert!(error.contains("WASM builds require LLVM"), "{error}");
        assert!(error.contains("brew install llvm"), "{error}");
        assert!(error.contains(missing), "{error}");
        assert!(!root.join("commands.log").exists());
    }
}

#[test]
fn invalid_explicit_compiler_is_reported_without_fallback() {
    let directory = fixture();
    let root = directory.path();
    install(&root.join("bin"));
    let output = command(root)
        .args(["check-sdk-bindings", "web"])
        .env("CC_wasm32_unknown_unknown", "missing-selected-clang")
        .output()
        .unwrap();
    assert!(!output.status.success());
    let error = String::from_utf8_lossy(&output.stderr);
    assert!(error.contains("CC_wasm32_unknown_unknown"), "{error}");
    assert!(error.contains("missing-selected-clang"), "{error}");
    assert!(!root.join("commands.log").exists());
}

#[test]
fn standard_build_configures_only_the_wasm_invocation() {
    let directory = fixture();
    let root = directory.path();
    install(&root.join("bin"));
    executable(
        &root.join("bin/cargo"),
        r#"#!/bin/sh
set -eu
[ "$CC" = native-compiler ]
[ "$AR" = native-archiver ]
case "$*" in
  *wasm32-unknown-unknown*)
    [ "$CC_wasm32_unknown_unknown" = clang ]
    [ "$AR_wasm32_unknown_unknown" = llvm-ar ]
    printf 'wasm\n' >> "$TEST_LOG" ;;
  *)
    [ -z "${CC_wasm32_unknown_unknown:-}" ]
    [ -z "${AR_wasm32_unknown_unknown:-}" ]
    printf 'native\n' >> "$TEST_LOG" ;;
esac
"#,
    );
    let output = command(root)
        .arg("build-sdk")
        .env("CC", "native-compiler")
        .env("AR", "native-archiver")
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        fs::read_to_string(root.join("commands.log")).unwrap(),
        "native\nwasm\n"
    );
}

#[cfg(target_os = "macos")]
#[test]
fn apple_clang_falls_back_to_homebrew_llvm() {
    let directory = fixture();
    let root = directory.path();
    let llvm = root.join("llvm/bin");
    install(&llvm);
    executable(
        &root.join("bin/clang"),
        "#!/bin/sh\nprintf 'arm64 - ARM64\n'\n",
    );
    executable(
        &root.join("bin/brew"),
        "#!/bin/sh\n[ \"$1\" = --prefix ] && [ \"$2\" = llvm ] || exit 99\nprintf '%s/llvm' \"$TEST_ROOT\"\n",
    );
    let output = command(root)
        .args(["check-sdk-bindings", "web"])
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        fs::read_to_string(root.join("commands.log")).unwrap(),
        format!(
            "{}|{}",
            llvm.join("clang").display(),
            llvm.join("llvm-ar").display()
        )
    );
}
