use crate::{DiagnosticLevel, DiagnosticPrivacy, diagnostics::delivery::emit};

pub(super) fn event(message: &'static str, model: &str, fields: &[(&str, f64)]) {
    emit(DiagnosticLevel::Info, "routing", message, |event| {
        event.field("model", DiagnosticPrivacy::Private, || model.into());
        for (name, value) in fields {
            event.field(name, DiagnosticPrivacy::Public, || value.to_string());
        }
        None
    });
}
