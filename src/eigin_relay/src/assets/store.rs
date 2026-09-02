//! The object-storage boundary: manifest fetch + presigned download URLs.
//!
//! `AssetStore` abstracts the S3 API the same way `SearchClient` /
//! `UpstreamClient` abstract theirs, so handlers are testable against an
//! in-memory fake. Presigning is local SigV4 math — no network I/O.

use std::fmt;
use std::sync::Arc;
use std::time::Duration;

use async_trait::async_trait;
use object_store::ObjectStoreExt;
use object_store::aws::{AmazonS3, AmazonS3Builder};
use object_store::path::Path;
use object_store::signer::Signer;
use reqwest::Method;
use url::Url;

/// Failures from the asset store, mapped to HTTP errors by the handler.
#[derive(Debug)]
pub enum AssetStoreError {
    /// The manifest object does not exist in the bucket.
    NotFound(String),
    /// Object storage unreachable or misconfigured.
    Unavailable(String),
}

impl fmt::Display for AssetStoreError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NotFound(key) => write!(f, "asset object not found: {key}"),
            Self::Unavailable(detail) => write!(f, "asset store unavailable: {detail}"),
        }
    }
}

impl std::error::Error for AssetStoreError {}

/// Read access to the asset mirror in object storage. Implementations must be
/// cheap to clone behind an `Arc` and safe to share across requests.
#[async_trait]
pub trait AssetStore: Send + Sync {
    /// Fetch the raw bytes of `assets/{id}/{version}/manifest.json`.
    async fn manifest_json(&self, id: &str, version: &str) -> Result<Vec<u8>, AssetStoreError>;

    /// Presign a GET for `assets/{id}/{version}/{path}` valid for `expires`.
    /// Signing is local SigV4 math — no network I/O — so it's safe to call per file.
    async fn presign(
        &self,
        id: &str,
        version: &str,
        path: &str,
        expires: Duration,
    ) -> Result<Url, AssetStoreError>;
}

/// Layout used by both the uploader and the relay:
/// `assets/{asset_id}/{version}/{…path}`.
pub fn object_key(asset_id: &str, version: &str, path: &str) -> String {
    format!("assets/{asset_id}/{version}/{path}")
}

/// Production store backed by Scaleway Object Storage (S3-compatible).
pub struct ScalewayAssetStore {
    s3: AmazonS3,
}

impl ScalewayAssetStore {
    /// Build from env vars (`ASSETS_BUCKET`, `S3_ENDPOINT`, `S3_REGION`,
    /// `S3_ACCESS_KEY`, `S3_SECRET_KEY`). All five must be set — a partially
    /// configured store is a deployment error, not a degraded mode.
    pub fn from_env() -> Option<Self> {
        let bucket = std::env::var("ASSETS_BUCKET").ok()?.trim().to_string();
        if bucket.is_empty() {
            return None;
        }
        Self::new(
            &bucket,
            &std::env::var("S3_ENDPOINT").ok()?,
            &std::env::var("S3_REGION").ok()?,
            &std::env::var("S3_ACCESS_KEY").ok()?,
            &std::env::var("S3_SECRET_KEY").ok()?,
        )
    }

    /// Returns `None` for any empty config value — the module then runs inert.
    fn new(
        bucket: &str,
        endpoint: &str,
        region: &str,
        access_key: &str,
        secret_key: &str,
    ) -> Option<Self> {
        if [bucket, endpoint, region, access_key, secret_key]
            .iter()
            .any(|v| v.trim().is_empty())
        {
            return None;
        }
        let s3 = AmazonS3Builder::new()
            .with_bucket_name(bucket)
            .with_endpoint(endpoint)
            .with_region(region)
            .with_access_key_id(access_key)
            .with_secret_access_key(secret_key)
            .with_allow_http(false)
            .build()
            .ok()?;
        Some(Self { s3 })
    }
}

#[async_trait]
impl AssetStore for ScalewayAssetStore {
    async fn manifest_json(&self, id: &str, version: &str) -> Result<Vec<u8>, AssetStoreError> {
        let key = Path::from(object_key(id, version, "manifest.json"));
        match self.s3.get(&key).await {
            Ok(result) => {
                let bytes = result.bytes().await;
                match bytes {
                    Ok(bytes) => Ok(bytes.to_vec()),
                    Err(e) => Err(AssetStoreError::Unavailable(e.to_string())),
                }
            }
            Err(object_store::Error::NotFound { path, .. }) => Err(AssetStoreError::NotFound(path)),
            Err(e) => Err(AssetStoreError::Unavailable(e.to_string())),
        }
    }

    async fn presign(
        &self,
        id: &str,
        version: &str,
        path: &str,
        expires: Duration,
    ) -> Result<Url, AssetStoreError> {
        let key = Path::from(object_key(id, version, path));
        self.s3
            .signed_url(Method::GET, &key, expires)
            .await
            .map_err(|e| AssetStoreError::Unavailable(e.to_string()))
    }
}

/// In-memory fake for tests.
pub struct InMemoryAssetStore {
    /// manifest bytes per `(id, version)`.
    manifests: std::collections::HashMap<(String, String), Vec<u8>>,
}

impl InMemoryAssetStore {
    pub fn new(manifests: std::collections::HashMap<(String, String), Vec<u8>>) -> Self {
        Self { manifests }
    }

    /// Convenience for a single manifest.
    pub fn with_manifest(id: &str, version: &str, bytes: Vec<u8>) -> Self {
        Self::new(
            [((id.to_string(), version.to_string()), bytes)]
                .into_iter()
                .collect(),
        )
    }
}

#[async_trait]
impl AssetStore for InMemoryAssetStore {
    async fn manifest_json(&self, id: &str, version: &str) -> Result<Vec<u8>, AssetStoreError> {
        self.manifests
            .get(&(id.to_string(), version.to_string()))
            .cloned()
            .ok_or_else(|| {
                AssetStoreError::NotFound(format!("assets/{id}/{version}/manifest.json"))
            })
    }

    async fn presign(
        &self,
        id: &str,
        version: &str,
        path: &str,
        expires: Duration,
    ) -> Result<Url, AssetStoreError> {
        Url::parse(&format!(
            "https://fake-bucket.s3.example.com/{}?expires={expires:?}",
            object_key(id, version, path)
        ))
        .map_err(|e| AssetStoreError::Unavailable(e.to_string()))
    }
}

/// Placeholder used when no bucket is configured. Every operation fails as
/// unavailable, so assets configured in the toml but lacking a bucket 503 at
/// serve time while an empty catalog stays fully inert (404s).
pub struct InertAssetStore;

#[async_trait]
impl AssetStore for InertAssetStore {
    async fn manifest_json(&self, id: &str, version: &str) -> Result<Vec<u8>, AssetStoreError> {
        Err(AssetStoreError::Unavailable(format!(
            "no asset store configured (requested {id}@{version})"
        )))
    }

    async fn presign(
        &self,
        _id: &str,
        _version: &str,
        _path: &str,
        _expires: Duration,
    ) -> Result<Url, AssetStoreError> {
        Err(AssetStoreError::Unavailable(
            "no asset store configured".into(),
        ))
    }
}

/// Type alias for how the store is shared in AppState.
pub type SharedAssetStore = Arc<dyn AssetStore>;
