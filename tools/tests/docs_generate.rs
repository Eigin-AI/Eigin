//! Exercise docs generation through the CLI with machine-local font inputs.
use sha2::{Digest, Sha256};
use std::{
    fs,
    os::unix::fs::PermissionsExt,
    process::{Command, Output},
};
use tempfile::TempDir;

fn fixture() -> TempDir {
    let dir = TempDir::new().unwrap();
    let root = dir.path();
    for path in [
        "bin",
        "design/assets/fonts/NorthEast",
        "docs/theme",
        "docs/src/fonts",
    ] {
        fs::create_dir_all(root.join(path)).unwrap();
    }
    fs::create_dir_all(root.join("LICENSES")).unwrap();
    fs::write(
        root.join("LICENSES/FiraCode-LICENSE.txt"),
        include_bytes!("../../LICENSES/FiraCode-LICENSE.txt"),
    )
    .unwrap();
    fs::write(root.join("bin/git"), "#!/bin/sh\npwd\n").unwrap();
    fs::set_permissions(root.join("bin/git"), fs::Permissions::from_mode(0o755)).unwrap();
    fs::write(
        root.join("design/tokens.json"),
        include_str!("../../design/tokens.json"),
    )
    .unwrap();
    let bytes = b"fixture font bytes";
    fs::write(
        root.join("design/assets/fonts/NorthEast/NorthEastCN-Bold copy.otf"),
        bytes,
    )
    .unwrap();
    fs::write(
        root.join("docs/fonts.json"),
        serde_json::to_vec(&serde_json::json!({
            "NorthEastCN-Bold.otf": hex::encode(Sha256::digest(bytes))
        }))
        .unwrap(),
    )
    .unwrap();
    fs::write(root.join("docs/src/fonts/stale.otf"), "stale").unwrap();
    dir
}

fn generate(dir: &TempDir) -> Output {
    Command::new(env!("CARGO_BIN_EXE_eigin-tools"))
        .current_dir(dir.path())
        .env(
            "PATH",
            format!(
                "{}:{}",
                dir.path().join("bin").display(),
                std::env::var("PATH").unwrap()
            ),
        )
        .args(["generate", "docs"])
        .output()
        .unwrap()
}

#[test]
fn bundles_verified_fonts_and_shared_tokens() {
    let dir = fixture();
    let output = generate(&dir);
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        fs::read(dir.path().join("docs/src/fonts/NorthEastCN-Bold.otf")).unwrap(),
        b"fixture font bytes"
    );
    assert!(!dir.path().join("docs/src/fonts/stale.otf").exists());
    assert_eq!(
        fs::read(dir.path().join("docs/src/fonts/FiraCode-LICENSE.txt")).unwrap(),
        include_bytes!("../../LICENSES/FiraCode-LICENSE.txt")
    );
    assert!(
        fs::read_to_string(dir.path().join("docs/theme/tokens.css"))
            .unwrap()
            .contains(":root.coal")
    );
}

#[test]
fn rejects_missing_fonts_before_building() {
    let dir = fixture();
    fs::remove_file(
        dir.path()
            .join("design/assets/fonts/NorthEast/NorthEastCN-Bold copy.otf"),
    )
    .unwrap();
    let output = generate(&dir);
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("Expected one source"));
}

#[test]
fn rejects_changed_font_bytes_before_building() {
    let dir = fixture();
    fs::write(
        dir.path()
            .join("design/assets/fonts/NorthEast/NorthEastCN-Bold copy.otf"),
        "unexpected",
    )
    .unwrap();
    let output = generate(&dir);
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("checksum mismatch"));
}

#[test]
fn secure_file_download_checks_selection_and_bytes() {
    for case in ["complete", "missing", "corrupt"] {
        let dir = fixture();
        let root = dir.path();
        fs::create_dir_all(root.join(".gitlab/scripts")).unwrap();
        fs::write(
            root.join(".gitlab/scripts/download-docs-fonts.sh"),
            include_str!("../../.gitlab/scripts/download-docs-fonts.sh"),
        )
        .unwrap();
        fs::write(
            root.join("bin/curl"),
            r#"#!/bin/sh
set -eu
for url do :; done
case "$url" in
  *secure_files\?per_page=100)
    if [ "$TEST_CASE" = missing ]; then printf '[]'; else
      printf '[{"id":7,"name":"NorthEastCN-Bold.otf"},{"id":99,"name":"unrelated.key"}]'
    fi ;;
  */7/download)
    if [ "$TEST_CASE" = corrupt ]; then printf 'corrupt'; else printf 'fixture font bytes'; fi ;;
  *) exit 99 ;;
esac
"#,
        )
        .unwrap();
        fs::set_permissions(root.join("bin/curl"), fs::Permissions::from_mode(0o755)).unwrap();
        let output = Command::new("bash")
            .arg(root.join(".gitlab/scripts/download-docs-fonts.sh"))
            .env(
                "PATH",
                format!(
                    "{}:{}",
                    root.join("bin").display(),
                    std::env::var("PATH").unwrap()
                ),
            )
            .env("CI_API_V4_URL", "https://gitlab.example.test/api/v4")
            .env("CI_PROJECT_ID", "1")
            .env("CI_JOB_TOKEN", "test-token")
            .env("TEST_CASE", case)
            .output()
            .unwrap();
        let downloaded = root.join("design/assets/fonts/docs/NorthEastCN-Bold.otf");
        if case == "complete" {
            assert!(
                output.status.success(),
                "{}",
                String::from_utf8_lossy(&output.stderr)
            );
            assert_eq!(fs::read(downloaded).unwrap(), b"fixture font bytes");
            assert!(!root.join("design/assets/fonts/docs/unrelated.key").exists());
        } else {
            assert!(!output.status.success());
            assert!(!downloaded.exists());
        }
    }
}
