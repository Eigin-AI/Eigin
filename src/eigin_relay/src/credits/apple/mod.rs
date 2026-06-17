//! Apple-specific credit integrations: JWS verification and App Store webhooks.

mod multi;
mod single;
mod verifier;
pub mod webhook;

pub use multi::MultiEnvironmentVerifier;
pub use single::AppStoreVerifier;
pub use verifier::{
    AppleEnvironment, AppleVerifier, NotificationType, VerifiedNotification, VerifiedTransaction,
    load_root_certs,
};
