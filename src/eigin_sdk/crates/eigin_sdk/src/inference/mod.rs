//! Inference messages, events and provider interfaces.
//! Hosts supply credentials, inventory and stream lifecycle; routing policy can select models.

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

pub mod anthropic;
pub use anthropic::*;

mod attempt;
pub use attempt::*;

pub mod routing;

pub mod local;
pub use local::*;
