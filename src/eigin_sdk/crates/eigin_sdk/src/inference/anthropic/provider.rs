use super::{
    super::request::request,
    operations::{AnthropicModelDiscovery, AnthropicValidation},
};
use super::{super::types::*, chat_stream::AnthropicStream};
use crate::http::*;
use std::sync::Arc;

/// Anthropic Messages provider behavior with injectable platform HTTP.
#[derive(uniffi::Object)]
pub struct AnthropicProvider {
    config: InferenceProviderConfig,
    transport: Arc<dyn HttpTransport>,
}

#[uniffi::export]
impl AnthropicProvider {
    /// Uses SDK-owned native HTTP. Browser hosts supply Fetch through with_transport.
    #[uniffi::constructor]
    pub fn new(config: InferenceProviderConfig) -> Result<Arc<Self>, InferenceError> {
        #[cfg(not(target_arch = "wasm32"))]
        {
            Ok(Arc::new(Self {
                config: super::request_body::config(config),
                transport: Arc::new(DefaultHttpTransport::new()?),
            }))
        }
        #[cfg(target_arch = "wasm32")]
        {
            let _ = config;
            Err(InferenceError::Transport {
                reason: "browser hosts must supply a Fetch transport".into(),
                domain: None,
                code: None,
            })
        }
    }

    /// Preserves platform networking while Rust owns requests and provider semantics.
    #[uniffi::constructor]
    pub fn with_transport(
        config: InferenceProviderConfig,
        transport: Box<dyn HttpTransport>,
    ) -> Arc<Self> {
        Arc::new(Self {
            config: super::request_body::config(config),
            transport: transport.into(),
        })
    }

    /// Creates a single-use model discovery operation; fetch_models starts I/O.
    pub fn discovery(&self) -> Arc<AnthropicModelDiscovery> {
        AnthropicModelDiscovery::new(self.config.clone(), self.transport.clone())
    }

    /// Creates a single-use credential check; validate_api_key starts I/O.
    pub fn key_validation(&self) -> Arc<AnthropicValidation> {
        AnthropicValidation::new(self.config.clone(), self.transport.clone())
    }

    /// Encodes a request without starting network I/O; open/next drive the operation.
    pub fn stream(
        &self,
        input: InferenceCompletionInput,
    ) -> Result<Arc<AnthropicStream>, InferenceError> {
        let body = super::request_body::encode(&input)?;
        let request = request(&self.config, "/messages", Some(body))?;
        Ok(AnthropicStream::new(
            HttpOperation::with_transport(self.transport.clone()),
            request,
            input,
        ))
    }
}
