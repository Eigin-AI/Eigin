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

/// Exercises typed errors in binding tests; excluded from application builds.
#[cfg(feature = "binding-tests")]
#[uniffi::export]
pub async fn fail_initialization_fixture() -> Result<(), InitializationError> {
    // Suspend once to exercise cross-language future wakeups.
    let mut yielded = false;
    std::future::poll_fn(|context| {
        if yielded {
            std::task::Poll::Ready(())
        } else {
            yielded = true;
            context.waker().wake_by_ref();
            std::task::Poll::Pending
        }
    })
    .await;
    Err(InitializationError::Unavailable {
        reason: "binding fixture".into(),
    })
}

#[cfg(test)]
mod tests {
    #[cfg(feature = "binding-tests")]
    #[test]
    fn error_fixture_suspends_before_returning_its_error() {
        use futures::FutureExt;
        assert!(
            super::fail_initialization_fixture()
                .now_or_never()
                .is_none()
        );
        let error = futures::executor::block_on(super::fail_initialization_fixture()).unwrap_err();
        assert!(
            matches!(error, super::InitializationError::Unavailable { reason } if reason == "binding fixture")
        );
    }

    #[test]
    fn initializes_repeatedly_without_host_services() {
        futures::executor::block_on(async {
            super::initialize().await.unwrap();
            super::initialize().await.unwrap();
        });
    }
}
