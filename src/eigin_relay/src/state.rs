//! Application state shared across all requests.

use std::sync::Arc;

use crate::search::{Pool, SearchClient};

/// Application state shared across all requests.
///
/// Contains the search client, configuration, and shared resources like
/// the rate limiter and quota pool.
pub struct AppState {
    /// Client for making upstream search requests.
    pub search_client: Arc<dyn SearchClient>,
    /// API key for the upstream search service (e.g., Mojeek).
    pub mojeek_api_key: String,
    /// Authentication key for this relay instance.
    pub eigin_relay_key: String,
    /// Monthly quota pool tracking remaining searches.
    pub pool: Pool,
    /// Per-IP rate limiter.
    pub rate_limiter: crate::RateLimiter,
}
