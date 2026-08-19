//! Eigin Relay — search proxy, rate limiting, quota management, and inference proxy.
//!
//! Provides:
//! - Anonymous search proxy with a shared rolling-window community pool.
//! - Anonymous inference proxy with a per-wallet credit ledger.

pub mod auth;
pub mod credits;
pub mod docs;
mod error;
mod health;
pub mod inference;
pub mod quota;
mod rate_limit;
pub mod search;
pub mod security;
mod state;

pub use auth::require_eigin_key;
pub use error::{AppError, log_errors};
pub use health::handler as health;
pub use quota::{Quota, QuotaError};
pub use rate_limit::RateLimiter;
pub use search::{SearchClient, SearchFocus, SearchOptions, create_client};
pub use security::security_headers;
pub use state::AppState;
