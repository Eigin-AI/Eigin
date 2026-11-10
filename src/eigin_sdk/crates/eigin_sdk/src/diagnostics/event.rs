//! Diagnostic observations and field classifications.

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
