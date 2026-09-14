//! Application state shared across all requests.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use crate::assets::cache::ManifestCache;
use crate::assets::catalog::AssetConfig;
use crate::assets::store::SharedAssetStore;
use crate::credits::CreditLedger;
use crate::credits::apple::AppleVerifier;
use crate::credits::grant::GrantVerifier;
use crate::inference::catalog::ModelConfig;
use crate::inference::upstream::UpstreamClient;
use crate::quota::Quota;
use crate::search::SearchClient;

/// Application state shared across all requests.
pub struct AppState {
    // --- Search ---
    /// Client for making upstream search requests.
    pub search_client: Arc<dyn SearchClient>,
    /// API key for the upstream search service (Staan).
    pub staan_api_key: String,
    /// Authentication keys this relay accepts (shared client gate). Normally the
    /// generated primary key; during a key rotation it also holds the previous
    /// (secondary) key so in-flight app builds keep working. A request is admitted
    /// if its `x-eigin-key` matches any of these.
    pub eigin_relay_keys: Vec<String>,
    /// Global per-IP rate limiter, applied as a blanket layer over every gated
    /// route (and `/docs`). Keyed on the client IP derived from `X-Forwarded-For`.
    pub ip_rate_limiter: crate::RateLimiter,
    /// Number of trusted proxy hops in front of the app, used to read the client
    /// IP from `X-Forwarded-For`. `1` behind Scaleway's ingress.
    pub trusted_proxy_hops: usize,
    /// Per-IP rate limiter for the unauthenticated Apple webhook. Separate from
    /// `ip_rate_limiter` so its window can be sized to Apple's retry cadence
    /// independent of search tuning.
    pub webhook_rate_limiter: crate::RateLimiter,
    /// Max searches the community pool allows within `search_window`.
    pub search_pool_max: u64,
    /// Trailing window over which the search community pool is measured.
    pub search_window: Duration,

    // --- Quota ---
    /// Rolling-window usage quota backing the search pool and sandbox budget.
    pub quota: Arc<dyn Quota>,

    // --- Credits ---
    /// The credit ledger. `InMemoryLedger` in dev/tests, `PostgresLedger` in production.
    pub ledger: Arc<dyn CreditLedger>,
    /// Apple JWS verifier. `AppStoreVerifier` in production, `FakeVerifier` in tests.
    pub apple_verifier: Arc<dyn AppleVerifier>,
    /// Grant JWT verifier. `Ed25519GrantVerifier` when a public key is configured,
    /// otherwise a verifier that rejects all grants.
    pub grant_verifier: Arc<dyn GrantVerifier>,
    /// Map from productId → millicredits.
    pub product_credits: HashMap<String, i64>,
    /// 32-byte AEAD key for encrypting tokens at rest (the primary). All new tokens are
    /// encrypted with this.
    pub token_encryption_key: [u8; 32],
    /// Optional previous key, set only during a rotation. Restore falls back to it so
    /// tokens encrypted before the rotation stay readable until a sweep re-encrypts them.
    pub token_encryption_key_secondary: Option<[u8; 32]>,
    /// Max sandbox credits this relay will issue within `sandbox_budget_window`.
    /// Bounds the cost of free TestFlight/App-Review (Sandbox) purchases.
    pub sandbox_budget_credits: u64,
    /// Trailing window over which the sandbox issuance budget is measured.
    pub sandbox_budget_window: Duration,

    // --- Inference ---
    /// Map of provider ID -> upstream client.
    pub provider_clients: HashMap<String, Arc<dyn UpstreamClient>>,
    /// Map of provider ID -> API key.
    pub provider_keys: HashMap<String, String>,
    /// Canonical model ID -> model config (rates, provider, upstream_id).
    pub canonical_models: HashMap<String, ModelConfig>,
    /// All accepted IDs (canonical + aliases) -> canonical ID.
    pub alias_map: HashMap<String, String>,
    /// Per-token rate limiter (keyed by wallet UUID).
    pub token_rate_limiter: crate::RateLimiter<uuid::Uuid>,

    // --- Model assets ---
    /// Configured assets (id → pinned version + manifest sha), from assets.toml.
    pub assets_config: HashMap<String, AssetConfig>,
    /// Lazy per-version manifest cache (fetch → sha-verify → parse → hold).
    pub assets_cache: ManifestCache,
    /// Object-storage boundary for the asset mirror; `InertAssetStore` when
    /// no bucket is configured (then entries -> 503 at serve time).
    pub asset_store: SharedAssetStore,
    /// How long presigned download URLs stay valid.
    pub presign_expiry: Duration,
}
