//! Application state shared across all requests.

use std::collections::HashMap;
use std::sync::Arc;

use crate::credits::CreditLedger;
use crate::credits::apple::AppleVerifier;
use crate::credits::grant::GrantVerifier;
use crate::inference::catalog::ModelConfig;
use crate::inference::upstream::UpstreamClient;
use crate::search::{Pool, SearchClient};

/// Application state shared across all requests.
pub struct AppState {
    // --- Search ---
    /// Client for making upstream search requests.
    pub search_client: Arc<dyn SearchClient>,
    /// API key for the upstream search service (e.g., Mojeek).
    pub mojeek_api_key: String,
    /// Authentication key for this relay instance (shared client gate).
    pub eigin_relay_key: String,
    /// Monthly quota pool tracking remaining searches.
    pub pool: Pool,
    /// Per-IP rate limiter (search + inference backstop).
    pub ip_rate_limiter: crate::RateLimiter,

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
    /// 32-byte AEAD key for encrypting tokens at rest.
    pub token_encryption_key: [u8; 32],

    // --- Inference ---
    /// Upstream inference client.
    pub upstream_client: Arc<dyn UpstreamClient>,
    /// API key for the upstream provider.
    pub upstream_api_key: Option<String>,
    /// Model rate map loaded from models.toml.
    pub model_rates: HashMap<String, ModelConfig>,
    /// Admit floor in millicredits — reject if balance < this.
    pub admit_floor_millicredits: i64,
    /// Per-token rate limiter (keyed by wallet UUID).
    pub token_rate_limiter: crate::RateLimiter<uuid::Uuid>,
}
