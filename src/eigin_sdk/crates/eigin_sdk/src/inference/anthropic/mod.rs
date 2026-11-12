//! Native Anthropic Messages protocol with host-supplied credentials and images.
mod chat_stream;
mod events;
mod operations;
mod provider;
mod request_body;
mod stream;
pub use chat_stream::AnthropicStream;
pub use operations::{AnthropicModelDiscovery, AnthropicValidation};
pub use provider::AnthropicProvider;

mod error;

#[cfg(test)]
mod tests;
