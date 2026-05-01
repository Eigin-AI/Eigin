//! Eigin Relay - A lightweight search API proxy with rate limiting and quota management.
//!
//! This crate provides a relay service that sits between clients and a search API (e.g., Mojeek).
//! It handles authentication, rate limiting per-IP, and monthly quota enforcement.

mod auth;
mod error;
mod health;
mod rate_limit;
pub mod search;
mod state;

pub use auth::require_eigin_key;
pub use error::AppError;
pub use health::handler as health;
pub use rate_limit::RateLimiter;
pub use search::{Pool, SearchClient, create_client};
pub use state::AppState;
