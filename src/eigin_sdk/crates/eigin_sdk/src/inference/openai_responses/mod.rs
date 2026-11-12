//! OpenAI Responses protocol for explicit ChatGPT-subscription credentials.
mod chat_stream;
mod error;
mod operations;
mod provider;
mod request_body;
mod stream;
pub use chat_stream::OpenAiResponsesStream;
pub use operations::{OpenAiResponsesModelDiscovery, OpenAiResponsesValidation};
pub use provider::OpenAiResponsesProvider;

#[cfg(test)]
mod tests;

mod event;
