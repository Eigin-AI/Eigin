use anyhow::{Context, Result};
use serde::Deserialize;
use std::collections::HashSet;
use std::fs;
use std::path::Path;

/// Keys intentionally exempt from the translation coverage check.
#[derive(Debug, Default)]
pub struct Allowlist {
    pub keys: HashSet<String>,
}

#[derive(Debug, Deserialize)]
struct AllowlistFile {
    #[serde(default)]
    keys: Vec<AllowlistEntry>,
}

#[derive(Debug, Deserialize)]
struct AllowlistEntry {
    key: String,
    #[allow(dead_code)]
    reason: String,
}

/// Load the allowlist from a TOML file at `path` (relative to `repo_root`).
///
/// A missing file means an empty allowlist — no obligation to add the file
/// just to enable the check.
pub fn load(repo_root: &str, path: &str) -> Result<Allowlist> {
    let full = format!("{repo_root}/{path}");
    if !Path::new(&full).exists() {
        return Ok(Allowlist::default());
    }
    let content = fs::read_to_string(&full).with_context(|| format!("reading {full}"))?;
    let file: AllowlistFile =
        toml::from_str(&content).with_context(|| format!("parsing allowlist {full}"))?;
    let keys = file.keys.into_iter().map(|e| e.key).collect();
    Ok(Allowlist { keys })
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn write(root: &TempDir, body: &str) {
        fs::write(root.path().join("allowlist.toml"), body).unwrap();
    }

    #[test]
    fn loads_keys_from_toml() {
        let dir = TempDir::new().unwrap();
        write(
            &dir,
            r#"
[[keys]]
key = "preview.sample"
reason = "Preview text."

[[keys]]
key = "credits.count"
reason = "Format only."
"#,
        );
        let list = load(dir.path().to_str().unwrap(), "allowlist.toml").unwrap();
        assert!(list.keys.contains("preview.sample"));
        assert!(list.keys.contains("credits.count"));
        assert_eq!(list.keys.len(), 2);
    }

    #[test]
    fn missing_file_is_empty_allowlist() {
        let dir = TempDir::new().unwrap();
        let list = load(dir.path().to_str().unwrap(), "absent.toml").unwrap();
        assert!(list.keys.is_empty());
    }

    #[test]
    fn empty_file_is_empty_allowlist() {
        let dir = TempDir::new().unwrap();
        write(&dir, "# nothing here\n");
        let list = load(dir.path().to_str().unwrap(), "allowlist.toml").unwrap();
        assert!(list.keys.is_empty());
    }

    #[test]
    fn errors_on_entry_without_key() {
        // A `[[keys]]` table missing the required `key` field is a malformed
        // allowlist; loading must fail rather than silently skip the entry.
        let dir = TempDir::new().unwrap();
        write(
            &dir,
            r#"
[[keys]]
reason = "no key here"
"#,
        );
        let result = load(dir.path().to_str().unwrap(), "allowlist.toml");
        assert!(result.is_err());
    }
}
