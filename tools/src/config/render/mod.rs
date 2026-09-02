//! Renderers project the resolved config into the form a consumer expects.

pub mod ios;
pub mod relay;
pub mod shell;
pub mod tf_vars;

/// A rendered environment: committed config and `.env` secrets together, in the
/// form one consumer expects.
///
/// Warnings carry values that are absent but optional, such as a relay key a
/// contributor can't obtain. Callers write them to stderr, because stdout is
/// consumed by `eval`.
#[derive(Debug)]
pub struct Rendered {
    pub exports: String,
    pub warnings: Vec<String>,
}

impl Rendered {
    pub fn new(exports: String, warnings: Vec<String>) -> Self {
        Rendered { exports, warnings }
    }
}
