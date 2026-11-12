//! OpenAI-compatible provider behavior and cancellable operations.

mod adapters;
mod chat_stream;
mod inference_diagnostics;
mod message;
mod operation_request;
mod operations;
mod provider;
mod reasoning;
mod request;
mod request_body;
mod stream;

use super::types;
pub use chat_stream::OpenAiCompatibleStream;
pub use operations::{ApiKeyValidationOperation, ModelDiscoveryOperation};
pub use provider::OpenAiCompatibleProvider;

#[cfg(test)]
mod tests;
