//! Initialization error fixture for host contracts.

use crate::InitializationError;

/// Returns a real SDK error through the generated bindings.
#[uniffi::export]
pub async fn fail_initialization_fixture() -> Result<(), InitializationError> {
    Err(InitializationError::Unavailable {
        reason: "binding fixture".into(),
    })
}
