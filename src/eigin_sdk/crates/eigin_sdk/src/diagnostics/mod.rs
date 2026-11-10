//! Structured, opt-in diagnostics routed to a host-owned receiver.

pub(crate) mod delivery;
mod event;

pub use delivery::{
    DiagnosticOptions, DiagnosticReceiver, clear_diagnostic_receiver, set_diagnostic_receiver,
    update_diagnostic_options,
};
pub use event::{
    DiagnosticContext, DiagnosticEvent, DiagnosticField, DiagnosticLevel, DiagnosticPrivacy,
};
