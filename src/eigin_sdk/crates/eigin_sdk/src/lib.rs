//! Portable entry point for the Eigin SDK.

#[cfg(target_arch = "wasm32")]
extern crate uniffi_runtime_wasm as _;

uniffi::setup_scaffolding!();

mod diagnostics;
pub use diagnostics::*;

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
