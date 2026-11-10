//! Diagnostic events emitted only by host contract builds.

use crate::diagnostics::{DiagnosticContext, DiagnosticLevel, DiagnosticPrivacy, emit};

/// Emits a representative event for cross-language tests.
#[cfg(feature = "binding-tests")]
#[uniffi::export]
pub fn emit_diagnostic_fixture() {
    emit(
        DiagnosticLevel::Info,
        "fixture",
        "Operation completed",
        |event| {
            for (name, value) in [
                ("operation", "test"),
                ("status", "ok"),
                ("count", "3"),
                ("duration_ms", "12"),
            ] {
                event.field(name, DiagnosticPrivacy::Public, || value.into());
            }
            event.field("detail", DiagnosticPrivacy::Private, || {
                "private fixture".into()
            });
            Some(DiagnosticContext {
                operation_id: "operation-1".into(),
                parent_operation_id: Some("parent-1".into()),
            })
        },
    );
}

/// Exercises native worker-thread callbacks through generated host bindings.
#[cfg(all(feature = "binding-tests", not(target_arch = "wasm32")))]
#[uniffi::export]
pub fn emit_diagnostic_worker_fixture() {
    std::thread::spawn(emit_diagnostic_fixture).join().unwrap();
}
