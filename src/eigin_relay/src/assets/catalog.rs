//! assets.toml loading: which asset versions are current.
//!
//! Loaded once at startup from the config path, same pattern as models.toml.

use serde::{Deserialize, Serialize};

/// A single `[[assets]]` entry in assets.toml.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct AssetConfig {
    pub id: String,
    pub version: String,
    /// sha256 (hex) of manifest.json — enforced at serve time. Pins the manifest
    /// bytes as well as the version, so an uploader credential alone can never
    /// change what apps download.
    pub manifest_sha256: String,
}

/// The full assets.toml structure.
#[derive(Debug, Deserialize)]
pub struct AssetsConfig {
    #[serde(default)]
    pub assets: Vec<AssetConfig>,
}

impl AssetsConfig {
    pub fn load(path: &str) -> Result<Self, String> {
        let content =
            std::fs::read_to_string(path).map_err(|e| format!("failed to read {path}: {e}"))?;
        toml::from_str(&content).map_err(|e| format!("failed to parse {path}: {e}"))
    }

    /// Build a lookup map from asset ID to config, rejecting duplicate IDs.
    pub fn into_map(self) -> Result<std::collections::HashMap<String, AssetConfig>, String> {
        let mut map = std::collections::HashMap::with_capacity(self.assets.len());
        for asset in self.assets {
            if map.contains_key(&asset.id) {
                return Err(format!("duplicate asset id: {}", asset.id));
            }
            map.insert(asset.id.clone(), asset);
        }
        Ok(map)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn write_config(dir: &std::path::Path, content: &str) -> String {
        let path = dir.join("assets.toml");
        std::fs::write(&path, content).unwrap();
        path.to_string_lossy().into_owned()
    }

    #[test]
    fn load_parses_entries() {
        let tmp = tempfile::tempdir().unwrap();
        let path = write_config(
            tmp.path(),
            r#"
[[assets]]
id = "gemma4-e2b"
version = "2026-01-15-1448"
manifest_sha256 = "abc123"
"#,
        );
        let config = AssetsConfig::load(&path).unwrap();
        assert_eq!(config.assets.len(), 1);
        assert_eq!(config.assets[0].id, "gemma4-e2b");
        assert_eq!(config.assets[0].version, "2026-01-15-1448");
    }

    #[test]
    fn load_accepts_empty_file() {
        let tmp = tempfile::tempdir().unwrap();
        let path = write_config(tmp.path(), "");
        let config = AssetsConfig::load(&path).unwrap();
        assert!(config.assets.is_empty());
    }

    #[test]
    fn load_rejects_missing_sha() {
        let tmp = tempfile::tempdir().unwrap();
        let path = write_config(
            tmp.path(),
            r#"
[[assets]]
id = "gemma4-e2b"
version = "2026-01-15-1448"
"#,
        );
        assert!(AssetsConfig::load(&path).is_err());
    }

    #[test]
    fn into_map_rejects_duplicate_ids() {
        let config = AssetsConfig {
            assets: vec![
                AssetConfig {
                    id: "pocket-tts".into(),
                    version: "1".into(),
                    manifest_sha256: "a".into(),
                },
                AssetConfig {
                    id: "pocket-tts".into(),
                    version: "2".into(),
                    manifest_sha256: "b".into(),
                },
            ],
        };
        assert!(config.into_map().is_err());
    }
}
