//! Relay authorization, wallet failover, and OpenAI-compatible inference.

mod authorization;
mod chat_stream;
mod provider;

pub use authorization::{EiginRelayWalletError, EiginRelayWalletSource};
pub use chat_stream::EiginRelayStream;
pub use provider::{EiginRelayProvider, EiginRelayProviderConfig};

#[cfg(test)]
mod tests;
