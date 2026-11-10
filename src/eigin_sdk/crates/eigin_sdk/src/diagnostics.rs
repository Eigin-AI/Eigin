//! Structured, opt-in diagnostics routed to a host-owned receiver.

use std::{
    cell::Cell,
    sync::{Arc, Mutex},
};

/// Diagnostic severity, ordered from least to most severe.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, uniffi::Enum)]
pub enum DiagnosticLevel {
    Debug,
    Info,
    Warning,
    Error,
}

/// Whether a field may be disclosed without explicit opt-in.
#[derive(Clone, Copy, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum DiagnosticPrivacy {
    Public,
    Private,
}

/// A named value; withheld private values retain their name and classification.
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct DiagnosticField {
    pub name: String,
    pub privacy: DiagnosticPrivacy,
    pub value: Option<String>,
}

/// Public, opaque correlation identifiers supplied by the operation's caller.
/// Use generated IDs without user content; these values are never redacted.
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct DiagnosticContext {
    pub operation_id: String,
    pub parent_operation_id: Option<String>,
}

/// One diagnostic observation. Messages and names are not stable control APIs.
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct DiagnosticEvent {
    pub level: DiagnosticLevel,
    pub component: String,
    pub message: String,
    pub context: Option<DiagnosticContext>,
    pub fields: Vec<DiagnosticField>,
}

/// Filtering applied before values are formatted or cross the host boundary.
#[derive(Clone, Copy, Debug, uniffi::Record)]
pub struct DiagnosticOptions {
    pub minimum_level: DiagnosticLevel,
    pub include_private: bool,
}

impl Default for DiagnosticOptions {
    fn default() -> Self {
        Self {
            minimum_level: DiagnosticLevel::Debug,
            include_private: false,
        }
    }
}

/// Host destination. Calls are synchronous and may arrive concurrently on native hosts.
/// Implementations must return quickly, never throw, and not call SDK operations.
#[uniffi::export(callback_interface)]
pub trait DiagnosticReceiver: Send + Sync {
    /// Receives a new event with private values already withheld unless opted in.
    fn receive(&self, event: DiagnosticEvent);
}

#[derive(Clone)]
struct Registration {
    receiver: Arc<dyn DiagnosticReceiver>,
    options: DiagnosticOptions,
}

static REGISTRATION: Mutex<Option<Registration>> = Mutex::new(None);
thread_local! { static DELIVERING: Cell<bool> = const { Cell::new(false) }; }

/// Replaces this SDK runtime's receiver. In-flight callbacks may still finish.
#[uniffi::export]
pub fn set_diagnostic_receiver(receiver: Box<dyn DiagnosticReceiver>, options: DiagnosticOptions) {
    let old = REGISTRATION.lock().unwrap().replace(Registration {
        receiver: receiver.into(),
        options,
    });
    // Host destruction can call foreign code; never hold the registration lock across it.
    drop(old);
}

/// Updates filtering for subsequent snapshots; already delivered values cannot be recalled.
#[uniffi::export]
pub fn update_diagnostic_options(options: DiagnosticOptions) {
    if let Some(registration) = REGISTRATION.lock().unwrap().as_mut() {
        registration.options = options;
    }
}

/// Detaches the receiver. In-flight callbacks retain it until they finish.
#[uniffi::export]
pub fn clear_diagnostic_receiver() {
    let old = REGISTRATION.lock().unwrap().take();
    drop(old);
}

/// Builder available only after the receiver and severity filters pass.
#[allow(dead_code)] // Used by binding fixtures until the first production SDK operation.
pub(crate) struct EventBuilder {
    include_private: bool,
    fields: Vec<DiagnosticField>,
}

#[allow(dead_code)] // Used by binding fixtures until the first production SDK operation.
impl EventBuilder {
    pub(crate) fn field(
        &mut self,
        name: &str,
        privacy: DiagnosticPrivacy,
        value: impl FnOnce() -> String,
    ) {
        let value = (privacy == DiagnosticPrivacy::Public || self.include_private).then(value);
        self.fields.push(DiagnosticField {
            name: name.into(),
            privacy,
            value,
        });
    }
}

/// Emits lazily so disabled diagnostics do not format fields or context.
#[allow(dead_code)] // Production operations will use this as they move into the SDK.
pub(crate) fn emit(
    level: DiagnosticLevel,
    component: &'static str,
    message: &'static str,
    build: impl FnOnce(&mut EventBuilder) -> Option<DiagnosticContext>,
) {
    if DELIVERING.get() {
        return;
    }
    let snapshot = REGISTRATION.lock().unwrap().clone();
    let Some(registration) = snapshot else {
        return;
    };
    if level < registration.options.minimum_level {
        return;
    }
    struct DeliveryGuard;
    impl Drop for DeliveryGuard {
        fn drop(&mut self) {
            DELIVERING.set(false);
        }
    }
    DELIVERING.set(true);
    let _guard = DeliveryGuard;
    let mut builder = EventBuilder {
        include_private: registration.options.include_private,
        fields: Vec::new(),
    };
    let context = build(&mut builder);
    registration.receiver.receive(DiagnosticEvent {
        level,
        component: component.into(),
        message: message.into(),
        context,
        fields: builder.fields,
    });
}

#[cfg(test)]
mod tests;
