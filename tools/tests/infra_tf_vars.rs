use std::fs;
use tempfile::TempDir;

use eigin_tools::infra::tf_vars::parse_dot_env;

// --- parse_dot_env unit tests ---

#[test]
fn parses_simple_key_value() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join(".env");
    fs::write(&path, "FOO=bar\n").unwrap();
    let map = parse_dot_env(path.to_str().unwrap());
    assert_eq!(map.get("FOO").map(String::as_str), Some("bar"));
}

#[test]
fn strips_export_prefix() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join(".env");
    fs::write(&path, "export FOO=bar\n").unwrap();
    let map = parse_dot_env(path.to_str().unwrap());
    assert_eq!(map.get("FOO").map(String::as_str), Some("bar"));
}

#[test]
fn strips_double_quotes() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join(".env");
    fs::write(&path, "export FOO=\"hello world\"\n").unwrap();
    let map = parse_dot_env(path.to_str().unwrap());
    assert_eq!(map.get("FOO").map(String::as_str), Some("hello world"));
}

#[test]
fn strips_single_quotes() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join(".env");
    fs::write(&path, "FOO='hello world'\n").unwrap();
    let map = parse_dot_env(path.to_str().unwrap());
    assert_eq!(map.get("FOO").map(String::as_str), Some("hello world"));
}

#[test]
fn skips_comments_and_blank_lines() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join(".env");
    fs::write(&path, "# comment\n\nFOO=bar\n").unwrap();
    let map = parse_dot_env(path.to_str().unwrap());
    assert_eq!(map.len(), 1);
    assert_eq!(map.get("FOO").map(String::as_str), Some("bar"));
}

#[test]
fn looks_up_env_suffixed_key() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join(".env");
    fs::write(
        &path,
        "export EIGIN_RELAY_PRIMARY_KEY_STAGING=stg-key\nexport EIGIN_RELAY_PRIMARY_KEY_PRODUCTION=prod-key\n",
    )
    .unwrap();
    let map = parse_dot_env(path.to_str().unwrap());
    assert_eq!(
        map.get("EIGIN_RELAY_PRIMARY_KEY_STAGING")
            .map(String::as_str),
        Some("stg-key")
    );
    assert_eq!(
        map.get("EIGIN_RELAY_PRIMARY_KEY_PRODUCTION")
            .map(String::as_str),
        Some("prod-key")
    );
}

#[test]
fn missing_file_returns_empty_map() {
    let map = parse_dot_env("/nonexistent/.env");
    assert!(map.is_empty());
}
