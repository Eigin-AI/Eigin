//! Inference messages, events and provider interfaces.
//! Hosts supply credentials, model selection and lifecycle policy.

pub mod openai_compatible;
mod types;

pub use openai_compatible::*;
pub use types::*;
