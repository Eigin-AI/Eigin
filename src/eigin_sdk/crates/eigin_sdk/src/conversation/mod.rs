//! Outgoing conversation preparation without storage, prompt gathering, or inference calls.

mod attachments;
mod equality;
mod hints;
mod preparation;
mod repair;
mod selection;
mod types;

pub use hints::conversation_append_hint;
pub use preparation::conversation_prepare;
pub use selection::conversation_select;
pub use types::*;

#[cfg(test)]
mod tests;
