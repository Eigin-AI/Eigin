//! Rolling-window usage quota.
//!
//! A `Quota` is a generic, durable flow cap: it accumulates `amount` against a
//! `key` and rejects a new consumption when the total within a trailing `window`
//! would exceed `max`.
//!
//! It backs both the shared search community pool and the Apple Sandbox
//! credit-issuance budget. The window is a per-call parameter so the period
//! can be retuned without a schema change.

mod bucket;
pub mod memory;
pub mod postgres;

use std::time::Duration;

use async_trait::async_trait;

pub use memory::InMemoryQuota;
pub use postgres::PostgresQuota;

/// Errors returned by a [`Quota`].
#[derive(Debug, thiserror::Error)]
pub enum QuotaError {
    /// The trailing-window total would exceed `max`.
    #[error("quota exhausted")]
    Exhausted,

    /// Something bad happened.
    #[error("quota error: {0}")]
    Internal(String),
}

/// A rolling-window flow cap keyed by an arbitrary string.
#[async_trait]
pub trait Quota: Send + Sync {
    /// Record a consumption of `amount` for `key`, rejecting with
    /// [`QuotaError::Exhausted`] if the total recorded within the trailing
    /// `window` would exceed `max`.
    async fn try_consume(
        &self,
        key: &str,
        amount: u64,
        max: u64,
        window: Duration,
    ) -> Result<(), QuotaError>;

    /// Remaining headroom for `key` over the trailing `window` given `max`.
    async fn remaining(&self, key: &str, max: u64, window: Duration) -> Result<u64, QuotaError>;
}
