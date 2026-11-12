//! Inference messages, events and provider interfaces.
//! Hosts supply credentials, model selection and lifecycle policy.

pub mod eigin_relay;
pub mod openai_compatible;
mod types;

pub use eigin_relay::*;
pub use openai_compatible::*;
pub use types::*;

mod inference_diagnostics;
pub mod openai_responses;
mod operation_request;
mod request;
pub use openai_responses::*;

mod streaming;
