use std::fs;
use tempfile::TempDir;

use eigin_tools::config::resolve::parse_dot_env;

fn dot_env(contents: &str) -> (TempDir, String) {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join(".env");
    fs::write(&path, contents).unwrap();
    let path = path.to_str().unwrap().to_string();
    (dir, path)
}

#[test]
fn parses_simple_key_value() {
    let (_dir, path) = dot_env("FOO=bar\n");
    assert_eq!(
        parse_dot_env(&path).get("FOO").map(String::as_str),
        Some("bar")
    );
}

#[test]
fn strips_export_prefix() {
    let (_dir, path) = dot_env("export FOO=bar\n");
    assert_eq!(
        parse_dot_env(&path).get("FOO").map(String::as_str),
        Some("bar")
    );
}

#[test]
fn strips_double_quotes() {
    let (_dir, path) = dot_env("export FOO=\"hello world\"\n");
    assert_eq!(
        parse_dot_env(&path).get("FOO").map(String::as_str),
        Some("hello world")
    );
}

#[test]
fn strips_single_quotes() {
    let (_dir, path) = dot_env("FOO='hello world'\n");
    assert_eq!(
        parse_dot_env(&path).get("FOO").map(String::as_str),
        Some("hello world")
    );
}

#[test]
fn skips_comments_and_blank_lines() {
    let (_dir, path) = dot_env("# comment\n\nFOO=bar\n");
    let map = parse_dot_env(&path);
    assert_eq!(map.len(), 1);
    assert_eq!(map.get("FOO").map(String::as_str), Some("bar"));
}

#[test]
fn reads_env_suffixed_keys() {
    let (_dir, path) = dot_env(
        "export EIGIN_RELAY_PRIMARY_KEY_STAGING=stg-key\nexport EIGIN_RELAY_PRIMARY_KEY_PRODUCTION=prod-key\n",
    );
    let map = parse_dot_env(&path);
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
    assert!(parse_dot_env("/nonexistent/.env").is_empty());
}
