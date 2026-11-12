use super::super::{operation_request::ProviderRequest, types::*};
use crate::http::HttpTransport;
use serde::Deserialize;
use std::sync::Arc;

#[derive(Deserialize)]
struct Models {
    data: Vec<Model>,
}

#[derive(Deserialize)]
struct Model {
    id: String,
}

/// Single-use Anthropic model discovery with explicit cancellation.
#[derive(uniffi::Object)]
pub struct AnthropicModelDiscovery {
    request: ProviderRequest,
}

impl AnthropicModelDiscovery {
    pub(super) fn new(
        config: InferenceProviderConfig,
        transport: Arc<dyn HttpTransport>,
    ) -> Arc<Self> {
        Arc::new(Self {
            request: ProviderRequest::for_provider(
                config,
                transport,
                "discovery",
                "inference.anthropic",
            ),
        })
    }
}

#[uniffi::export]
impl AnthropicModelDiscovery {
    /// Returns model IDs sorted lexically, preserving duplicate entries.
    pub async fn fetch_models(&self) -> Result<Vec<String>, InferenceError> {
        self.request
            .run(None, async {
                let head = self.request.send("/models", None).await?;
                if !(200..300).contains(&head.status) {
                    return Err(InferenceError::Http {
                        status: head.status,
                        body: None,
                    });
                }
                let models: Models = serde_json::from_slice(&self.request.read_body().await?)?;
                let mut ids: Vec<_> = models.data.into_iter().map(|model| model.id).collect();
                ids.sort();
                Ok(ids)
            })
            .await
    }

    /// Cancels pending discovery work.
    pub fn cancel(&self) {
        self.request.cancel();
    }
}

/// Single-use Anthropic credential validation with explicit cancellation.
#[derive(uniffi::Object)]
pub struct AnthropicValidation {
    request: ProviderRequest,
}

impl AnthropicValidation {
    pub(super) fn new(
        config: InferenceProviderConfig,
        transport: Arc<dyn HttpTransport>,
    ) -> Arc<Self> {
        Arc::new(Self {
            request: ProviderRequest::for_provider(
                config,
                transport,
                "key validation",
                "inference.anthropic",
            ),
        })
    }
}

#[uniffi::export]
impl AnthropicValidation {
    /// Only 401/403 invalidate credentials, preserving existing host behavior.
    pub async fn validate_api_key(&self, model: String) -> Result<(), InferenceError> {
        self.request
            .run(Some(&model), async {
                let head = self
                    .request
                    .send("/messages", Some(super::request_body::validation(&model)))
                    .await?;
                self.request.read_body().await?;
                if head.status == 401 || head.status == 403 {
                    return Err(InferenceError::Http {
                        status: head.status,
                        body: None,
                    });
                }
                Ok(())
            })
            .await
    }

    /// Cancels pending validation work.
    pub fn cancel(&self) {
        self.request.cancel();
    }
}
