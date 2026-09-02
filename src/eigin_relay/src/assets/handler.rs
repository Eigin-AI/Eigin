//! GET /v1/assets and GET /v1/assets/{id} handlers.

use std::sync::Arc;

use axum::Json;
use axum::extract::{Path, State};
use axum::response::IntoResponse;
use serde::Serialize;

use crate::AppState;
use crate::assets::cache::{AssetManifestResponse, ManifestCache, ManifestFileResponse};
use crate::assets::catalog::AssetConfig;
use crate::error::AppError;

/// `GET /v1/assets` — every configured asset and its current version. Served
/// straight from assets.toml; no store access, so it works even while the
/// bucket is unreachable.
pub async fn handle_list(
    State(state): State<Arc<AppState>>,
) -> Result<impl IntoResponse, AppError> {
    let mut assets: Vec<AssetListEntry> = state
        .assets_config
        .values()
        .map(|a| AssetListEntry {
            id: a.id.clone(),
            version: a.version.clone(),
        })
        .collect();
    assets.sort_unstable_by(|a, b| a.id.cmp(&b.id));
    Ok(Json(AssetsListResponse { assets }))
}

#[derive(Serialize)]
pub struct AssetsListResponse {
    pub assets: Vec<AssetListEntry>,
}

#[derive(Serialize)]
pub struct AssetListEntry {
    pub id: String,
    pub version: String,
}

/// `GET /v1/assets/{id}` — the pinned version's manifest plus presigned GET
/// URLs for every file.
pub async fn handle_get(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> Result<Json<AssetManifestResponse>, AppError> {
    let config = state
        .assets_config
        .get(&id)
        .cloned()
        .ok_or(AppError::AssetNotFound)?;

    serve_asset(
        &config,
        &state.assets_cache,
        state.asset_store.as_ref(),
        state.presign_expiry,
    )
    .await
}

/// Shared body: fetch/verify/parse the manifest, then presign every file.
async fn serve_asset(
    config: &AssetConfig,
    cache: &ManifestCache,
    store: &dyn crate::assets::store::AssetStore,
    presign_expiry: std::time::Duration,
) -> Result<Json<AssetManifestResponse>, AppError> {
    let manifest = cache
        .get(store, &config.id, &config.version, &config.manifest_sha256)
        .await
        .map_err(|e| match e {
            crate::assets::cache::ManifestCacheError::ShaMismatch { id, version } => {
                tracing::error!(asset = %id, version = %version, "manifest sha256 mismatch");
                AppError::ServiceUnavailable("asset manifest mismatch".into())
            }
            crate::assets::cache::ManifestCacheError::Store(
                crate::assets::store::AssetStoreError::Unavailable(detail),
            ) => {
                tracing::error!(asset = %config.id, %detail, "asset store unavailable");
                AppError::ServiceUnavailable("asset store unavailable".into())
            }
            crate::assets::cache::ManifestCacheError::Store(
                crate::assets::store::AssetStoreError::NotFound(key),
            ) => {
                tracing::error!(asset = %config.id, key = %key, "manifest object missing");
                AppError::ServiceUnavailable("asset manifest missing".into())
            }
            crate::assets::cache::ManifestCacheError::Unmarshal(detail) => {
                tracing::error!(asset = %config.id, %detail, "manifest parse failed");
                AppError::ServiceUnavailable("asset manifest unreadable".into())
            }
        })?;

    use futures::TryStreamExt;
    let asset_id = manifest.asset_id.clone();
    let version = manifest.version.clone();
    let files: Vec<ManifestFileResponse> = manifest
        .files
        .iter()
        .map(|file| {
            let asset_id = &asset_id;
            let version = &version;
            async move {
                let url = store
                    .presign(asset_id, version, &file.path, presign_expiry)
                    .await
                    .map_err(|e| {
                        tracing::error!(asset = %config.id, error = %e, "presign failed");
                        AppError::ServiceUnavailable("asset store unavailable".into())
                    })?;
                Ok(ManifestFileResponse {
                    path: file.path.clone(),
                    size: file.size,
                    sha256: file.sha256.clone(),
                    url: url.to_string(),
                })
            }
        })
        .collect::<futures::stream::FuturesOrdered<_>>()
        .try_collect()
        .await?;

    Ok(Json(AssetManifestResponse {
        id: manifest.asset_id,
        version: manifest.version,
        files,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::assets::cache::AssetManifest;
    use crate::assets::store::InMemoryAssetStore;
    use crate::assets::{ManifestFile, ManifestOrigin};
    use std::collections::HashMap;
    use std::time::Duration;

    fn manifest_bytes(id: &str, version: &str) -> Vec<u8> {
        serde_json::to_vec(&AssetManifest {
            asset_id: id.into(),
            version: version.into(),
            origin: Some(ManifestOrigin {
                repo: "r/l".into(),
                revision: "c0".into(),
            }),
            files: vec![
                ManifestFile {
                    path: "a.bin".into(),
                    size: 10,
                    sha256: "aa".into(),
                },
                ManifestFile {
                    path: "b.bin".into(),
                    size: 20,
                    sha256: "bb".into(),
                },
            ],
        })
        .unwrap()
    }

    fn config(id: &str, version: &str, sha: &str) -> AssetConfig {
        AssetConfig {
            id: id.into(),
            version: version.into(),
            manifest_sha256: sha.into(),
        }
    }

    async fn serve(
        config: AssetConfig,
        store: &dyn crate::assets::store::AssetStore,
    ) -> Result<Json<AssetManifestResponse>, AppError> {
        let cache = ManifestCache::default();
        serve_asset(&config, &cache, store, Duration::from_secs(3600)).await
    }

    #[tokio::test]
    async fn get_serves_manifest_with_presigned_urls() {
        let id = "gemma4-e2b";
        let version = "2026-01-15-1448";
        let bytes = manifest_bytes(id, version);
        let sha = crate::assets::cache::sha256_hex(&bytes);
        let store = InMemoryAssetStore::with_manifest(id, version, bytes);

        let response = serve(config(id, version, &sha), &store).await.unwrap().0;
        assert_eq!(response.id, id);
        assert_eq!(response.version, version);
        assert_eq!(response.files.len(), 2);
        assert_eq!(response.files[0].path, "a.bin");
        assert!(
            response.files[0]
                .url
                .contains("assets/gemma4-e2b/2026-01-15-1448/a.bin")
        );
    }

    #[tokio::test]
    async fn sha_mismatch_returns_503() {
        let id = "plapre-pico";
        let version = "2026-01-15-1448";
        let store = InMemoryAssetStore::with_manifest(id, version, manifest_bytes(id, version));
        let err = serve(config(id, version, "not-the-sha"), &store)
            .await
            .unwrap_err();
        assert!(matches!(err, AppError::ServiceUnavailable(_)));
    }

    #[tokio::test]
    async fn unknown_manifest_object_returns_503() {
        // Configured in assets.toml but the bucket lacks the manifest object:
        // pointer drift — 503, not 404, so clients retry.
        let id = "pocket-tts";
        let store = InMemoryAssetStore::new(HashMap::new());
        let err = serve(config(id, "2026-01-15-1448", "any"), &store)
            .await
            .unwrap_err();
        assert!(matches!(err, AppError::ServiceUnavailable(_)));
    }
}
