use super::{operation_request::ProviderRequest, types::*};
use crate::http::*;
use serde::Deserialize;
use serde_json::json;
use std::sync::Arc;

/// Single-use model discovery with explicit cancellation across host bindings.
#[derive(uniffi::Object)]
pub struct ModelDiscoveryOperation {
    request: ProviderRequest,
}

impl ModelDiscoveryOperation {
    pub(super) fn new(
        config: InferenceProviderConfig,
        transport: Arc<dyn HttpTransport>,
    ) -> Arc<Self> {
        Arc::new(Self {
            request: ProviderRequest::new(config, transport, "discovery"),
        })
    }
}

#[uniffi::export]
impl ModelDiscoveryOperation {
    /// Fetches deduplicated model IDs in sorted order.
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

                let bytes = self.request.read_body().await?;
                let models: ModelList = serde_json::from_slice(&bytes)?;
                let mut ids: Vec<_> = models.data.into_iter().map(|model| model.id).collect();
                ids.sort();
                ids.dedup();
                Ok(ids)
            })
            .await
    }

    /// Aborts pending network work, including a pending fetch_models call.
    pub fn cancel(&self) {
        self.request.cancel();
    }
}

/// Single-use credential validation with explicit cancellation across host bindings.
#[derive(uniffi::Object)]
pub struct ApiKeyValidationOperation {
    request: ProviderRequest,
}

impl ApiKeyValidationOperation {
    pub(super) fn new(
        config: InferenceProviderConfig,
        transport: Arc<dyn HttpTransport>,
    ) -> Arc<Self> {
        Arc::new(Self {
            request: ProviderRequest::new(config, transport, "key validation"),
        })
    }
}

#[uniffi::export]
impl ApiKeyValidationOperation {
    /// Only 401/403 prove invalid credentials; other statuses are inconclusive.
    pub async fn validate_api_key(&self, model: String) -> Result<(), InferenceError> {
        self.request
            .run(Some(&model), async {
                let body = serde_json::to_vec(&json!({
                    "model": model,
                    "messages": [{"role": "user", "content": "hi"}],
                    "stream": false,
                    "max_tokens": 1,
                }))?;
                let head = self.request.send("/chat/completions", Some(body)).await?;
                if head.status == 401 || head.status == 403 {
                    return Err(InferenceError::Http {
                        status: head.status,
                        body: None,
                    });
                }

                // Draining preserves transport failures after successful response headers.
                self.request.read_body().await?;
                Ok(())
            })
            .await
    }

    /// Aborts pending network work, including a pending validate_api_key call.
    pub fn cancel(&self) {
        self.request.cancel();
    }
}

#[derive(Deserialize)]
struct ModelList {
    data: Vec<ModelId>,
}

#[derive(Deserialize)]
struct ModelId {
    id: String,
}
