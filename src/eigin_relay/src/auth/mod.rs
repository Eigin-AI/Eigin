//! Authentication and request identity.
//!
//! - [`key`]: `x-eigin-key` middleware — gates all routes to Eigin clients.
//! - [`bearer`]: Bearer token extractor — resolves a credit token to a wallet.

mod bearer;
mod key;

pub use bearer::{WalletBearer, extract_bearer_token};
pub use key::require_eigin_key;
