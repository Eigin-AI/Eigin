use super::super::{operation_request::ProviderRequest, types::*};
use crate::http::HttpTransport;
use serde::Deserialize;
use std::{collections::HashSet, sync::Arc};

/// Single-use OpenAI Responses model discovery with explicit cancellation.
#[derive(uniffi::Object)]
pub struct OpenAiResponsesModelDiscovery {
    request: ProviderRequest,
}

impl OpenAiResponsesModelDiscovery {
    pub(super) fn new(
        config: InferenceProviderConfig,
        transport: Arc<dyn HttpTransport>,
    ) -> Arc<Self> {
        Arc::new(Self {
            request: ProviderRequest::for_provider(
                config,
                transport,
                "discovery",
                "inference.openai-responses",
            ),
        })
    }
}

#[uniffi::export]
impl OpenAiResponsesModelDiscovery {
    /// Returns visible model IDs in server order, without duplicates.
    pub async fn fetch_models(&self) -> Result<Vec<String>, InferenceError> {
        self.request
            .run(None, async {
                let head = self.request.send("/models", None).await?;
                let bytes = self.request.read_body().await?;
                if !(200..300).contains(&head.status) {
                    return Err(super::error::normalize(
                        head.status,
                        String::from_utf8(bytes).ok(),
                    ));
                }
                let models: Models = serde_json::from_slice(&bytes)?;
                let ids = if let Some(models) = models.models {
                    models
                        .into_iter()
                        .filter(|m| m.visibility.as_deref().is_none_or(|v| v == "list"))
                        .filter_map(|m| m.slug.or(m.id))
                        .collect::<Vec<_>>()
                } else {
                    models
                        .data
                        .unwrap_or_default()
                        .into_iter()
                        .map(|m| m.id)
                        .collect()
                };
                let mut seen = HashSet::new();
                Ok(ids
                    .into_iter()
                    .filter(|id| seen.insert(id.clone()))
                    .collect())
            })
            .await
    }
    /// Cancels pending discovery work.
    pub fn cancel(&self) {
        self.request.cancel();
    }
}

/// Single-use ChatGPT credential validation with explicit cancellation.
#[derive(uniffi::Object)]
pub struct OpenAiResponsesValidation {
    request: ProviderRequest,
}

impl OpenAiResponsesValidation {
    pub(super) fn new(
        config: InferenceProviderConfig,
        transport: Arc<dyn HttpTransport>,
    ) -> Arc<Self> {
        Arc::new(Self {
            request: ProviderRequest::for_provider(
                config,
                transport,
                "key validation",
                "inference.openai-responses",
            ),
        })
    }
}

#[uniffi::export]
impl OpenAiResponsesValidation {
    /// Only 401/403 invalidate sign-in; other statuses retain legacy validation semantics.
    pub async fn validate_api_key(&self, model: String) -> Result<(), InferenceError> {
        self.request
            .run(Some(&model), async {
                let body = super::request_body::encode(&InferenceCompletionInput {
                    model: model.clone(),
                    messages: vec![InferenceMessage {
                        role: "user".into(),
                        content: Some("hi".into()),
                        ..Default::default()
                    }],
                    ..Default::default()
                })?;
                let head = self.request.send("/responses", Some(body)).await?;
                self.request.read_body().await?;
                if head.status == 401 || head.status == 403 {
                    return Err(InferenceError::SubscriptionInvalidUser);
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

#[derive(Deserialize)]
struct Models {
    models: Option<Vec<SubscriptionModel>>,
    data: Option<Vec<Model>>,
}
#[derive(Deserialize)]
struct SubscriptionModel {
    slug: Option<String>,
    id: Option<String>,
    visibility: Option<String>,
}
#[derive(Deserialize)]
struct Model {
    id: String,
}
