//! The asset manifest as the relay serves it, plus the lazy per-version cache.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use tokio::sync::Mutex;

use crate::assets::store::AssetStore;

/// `manifest.json` as written by the uploader.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AssetManifest {
    pub asset_id: String,
    pub version: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub origin: Option<ManifestOrigin>,
    pub files: Vec<ManifestFile>,
}

/// Upstream provenance, recorded for audit.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ManifestOrigin {
    pub repo: String,
    pub revision: String,
}

/// One file in a manifest: path relative to the version prefix.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ManifestFile {
    pub path: String,
    pub size: u64,
    pub sha256: String,
}

/// `GET /v1/assets/{id}` response body: the manifest plus presigned URLs.
#[derive(Debug, Serialize)]
pub struct AssetManifestResponse {
    pub id: String,
    pub version: String,
    pub files: Vec<ManifestFileResponse>,
}

#[derive(Debug, Serialize)]
pub struct ManifestFileResponse {
    pub path: String,
    pub size: u64,
    pub sha256: String,
    pub url: String,
}

/// Lazy cache of parsed manifests, keyed by (id, version).
///
/// Entries are immutable per key: a deploy swaps versions, never rewrites one,
/// so the cache never needs invalidation.
pub struct ManifestCache {
    inner: Mutex<HashMap<(String, String), AssetManifest>>,
}

impl ManifestCache {
    /// Fetch, verify against the pinned sha256, parse, and cache. The sha256
    /// check runs on every miss — a mismatch means the bucket and assets.toml
    /// have drifted apart.
    pub async fn get(
        &self,
        store: &dyn AssetStore,
        id: &str,
        version: &str,
        expected_sha256: &str,
    ) -> Result<AssetManifest, ManifestCacheError> {
        // Fast path: a previous hit already parsed and cached it.
        if let Some(cached) = self
            .inner
            .lock()
            .await
            .get(&(id.to_string(), version.to_string()))
        {
            return Ok(cached.clone());
        }

        let bytes = store
            .manifest_json(id, version)
            .await
            .map_err(ManifestCacheError::from)?;

        let digest = sha256_hex(&bytes);
        if !digest.eq_ignore_ascii_case(expected_sha256) {
            return Err(ManifestCacheError::ShaMismatch {
                id: id.into(),
                version: version.into(),
            });
        }

        let manifest: AssetManifest = serde_json::from_slice(&bytes)
            .map_err(|e| ManifestCacheError::Unmarshal(e.to_string()))?;

        self.inner
            .lock()
            .await
            .insert((id.to_string(), version.to_string()), manifest.clone());
        Ok(manifest)
    }
}

impl Default for ManifestCache {
    fn default() -> Self {
        Self {
            inner: Mutex::new(HashMap::new()),
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum ManifestCacheError {
    #[error(transparent)]
    Store(#[from] crate::assets::store::AssetStoreError),
    #[error(
        "manifest sha256 mismatch for {id}@{version}: bucket contents and assets.toml disagree"
    )]
    ShaMismatch { id: String, version: String },
    #[error("failed to parse manifest: {0}")]
    Unmarshal(String),
}

/// sha256 of arbitrary bytes as lowercase hex.
pub fn sha256_hex(bytes: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    let digest = Sha256::digest(bytes);
    hex::encode(digest)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::assets::store::InMemoryAssetStore;
    use std::collections::HashMap;

    fn test_manifest(id: &str, version: &str) -> Vec<u8> {
        serde_json::to_vec(&AssetManifest {
            asset_id: id.into(),
            version: version.into(),
            origin: Some(ManifestOrigin {
                repo: "some/repo".into(),
                revision: "abc".into(),
            }),
            files: vec![ManifestFile {
                path: "model.bin".into(),
                size: 42,
                sha256: "deadbeef".into(),
            }],
        })
        .unwrap()
    }

    #[tokio::test]
    async fn caches_after_first_fetch() {
        let id = "gemma4-e2b";
        let version = "2026-01-15-1448";
        let bytes = test_manifest(id, version);
        let sha = sha256_hex(&bytes);
        let store = InMemoryAssetStore::with_manifest(id, version, bytes.clone());

        let cache = ManifestCache::default();
        let m1 = cache
            .get(&store, id, version, &sha)
            .await
            .expect("first fetch");
        let m2 = cache
            .get(&store, id, version, &sha)
            .await
            .expect("second fetch");
        assert_eq!(m1.files.len(), 1);
        assert_eq!(m1.files[0].path, "model.bin");
        assert_eq!(m2.version, version);
    }

    #[tokio::test]
    async fn sha_mismatch_is_an_error() {
        let id = "gemma4-e2b";
        let version = "2026-01-15-1448";
        let store = InMemoryAssetStore::with_manifest(id, version, test_manifest(id, version));

        let cache = ManifestCache::default();
        let err = cache
            .get(&store, id, version, "wrongsha")
            .await
            .unwrap_err();
        assert!(matches!(err, ManifestCacheError::ShaMismatch { .. }));
    }

    #[tokio::test]
    async fn missing_object_propagates() {
        let store = InMemoryAssetStore::new(HashMap::new());
        let cache = ManifestCache::default();
        let err = cache.get(&store, "nonsense", "1", "x").await.unwrap_err();
        assert!(matches!(
            err,
            ManifestCacheError::Store(crate::assets::store::AssetStoreError::NotFound(_))
        ));
    }
}
