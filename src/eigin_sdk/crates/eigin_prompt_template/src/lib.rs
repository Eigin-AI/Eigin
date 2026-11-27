//! Shared limited prompt syntax and include validation for runtime and generation.
pub mod parser;
mod resolve;
pub use resolve::resolve_all_params;

/// Parsed templates keyed by catalog-local name.
pub type Templates = std::collections::BTreeMap<String, Vec<parser::Segment>>;
