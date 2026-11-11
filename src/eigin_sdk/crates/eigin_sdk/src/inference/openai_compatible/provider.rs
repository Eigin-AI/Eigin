use super::{adapters::Adapter, chat_stream::InferenceStream, types::*};
use super::{
    operations::{ApiKeyValidationOperation, ModelDiscoveryOperation},
    request::request,
};
use crate::http::*;
use std::sync::Arc;

/// OpenAI-compatible provider behavior with injectable platform HTTP.
#[derive(uniffi::Object)]
pub struct OpenAiCompatibleProvider {
    config: InferenceProviderConfig,
    transport: Arc<dyn HttpTransport>,
}

#[uniffi::export]
impl OpenAiCompatibleProvider {
    /// Uses SDK-owned native HTTP. Browser hosts supply Fetch through with_transport.
    #[uniffi::constructor]
    pub fn new(config: InferenceProviderConfig) -> Result<Arc<Self>, InferenceError> {
        #[cfg(not(target_arch = "wasm32"))]
        {
            Ok(Arc::new(Self {
                config,
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
            config,
            transport: transport.into(),
        })
    }

    /// Creates a single-use model discovery operation; fetch_models starts I/O.
    pub fn discovery(&self) -> Arc<ModelDiscoveryOperation> {
        ModelDiscoveryOperation::new(self.config.clone(), self.transport.clone())
    }

    /// Creates a single-use credential check; validate_api_key starts I/O.
    pub fn key_validation(&self) -> Arc<ApiKeyValidationOperation> {
        ApiKeyValidationOperation::new(self.config.clone(), self.transport.clone())
    }

    /// Encodes a request without starting network I/O; open/next drive the operation.
    pub fn stream(
        &self,
        input: InferenceCompletionInput,
    ) -> Result<Arc<InferenceStream>, InferenceError> {
        let adapter = Adapter::select(&self.config.base_url, &input);
        let body = adapter.request(&input)?;
        let request = request(&self.config, "/chat/completions", Some(body))?;
        Ok(InferenceStream::new(
            HttpOperation::with_transport(self.transport.clone()),
            request,
            adapter,
            input,
        ))
    }
}
