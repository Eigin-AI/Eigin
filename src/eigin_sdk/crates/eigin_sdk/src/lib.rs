//! Portable entry point for the Eigin SDK.

#[cfg(target_arch = "wasm32")]
extern crate uniffi_runtime_wasm as _;

uniffi::setup_scaffolding!();

/// Context estimation, selection, and summary parsing.
pub mod context;
mod diagnostics;
/// Platform HTTP byte transport and cancellation.
pub mod http;
/// Portable inference provider operations.
pub mod inference;

pub use diagnostics::*;

/// License and copyright notices for SDK runtime dependencies across supported hosts.
pub const THIRD_PARTY_NOTICES: &str = include_str!("../../../THIRD-PARTY-NOTICES.txt");

/// A failure while preparing the SDK for use.
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum InitializationError {
    /// A required SDK capability is unavailable.
    #[error("SDK initialization unavailable: {reason}")]
    Unavailable { reason: String },
}

/// Initializes the SDK without storage, network access, or platform services.
///
/// Repeated calls are safe. Initialization currently needs no shared state.
#[uniffi::export]
pub async fn initialize() -> Result<(), InitializationError> {
    Ok(())
}

#[cfg(feature = "binding-tests")]
mod binding_tests;

#[cfg(test)]
mod tests {
    #[test]
    fn initializes_repeatedly_without_host_services() {
        futures::executor::block_on(async {
            super::initialize().await.unwrap();
            super::initialize().await.unwrap();
        });
    }
}
