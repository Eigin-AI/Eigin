use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Endpoint and explicit credentials for one OpenAI-compatible provider.
#[derive(Clone, Debug, uniffi::Record)]
pub struct InferenceProviderConfig {
    pub base_url: String,
    /// An empty token omits the default Authorization header; explicit extra headers still apply.
    pub api_token: String,
    pub extra_headers: HashMap<String, String>,
}

/// Catalog information supplied by the host for routed models.
#[derive(Clone, Copy, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum InferenceModelFamily {
    Google,
    Mistral,
    Anthropic,
    Other,
}

/// Function invocation; arguments retain the provider's JSON text.
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct InferenceToolCall {
    pub id: String,
    pub kind: String,
    pub name: String,
    pub arguments: String,
}

/// Resolved image bytes. Attachment storage remains a host responsibility.
#[derive(Clone, Debug, uniffi::Record)]
pub struct InferenceImage {
    pub mime_type: String,
    pub bytes: Vec<u8>,
}

/// Origin identity supplied by the host; it must match exactly for reasoning replay.
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct InferenceReasoningOrigin {
    pub provider_id: String,
    pub endpoint: String,
    pub model: String,
}

/// Opaque provider continuation state; never persist without its origin.
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct InferenceReasoningHistory {
    pub origin: InferenceReasoningOrigin,
    pub format: String,
    pub payload: Vec<u8>,
    pub visible_text: String,
    pub additional_input_tokens: i64,
}

/// Request-only message values, independent of host persistence.
#[derive(Clone, Debug, Default, uniffi::Record)]
pub struct InferenceMessage {
    pub role: String,
    pub content: Option<String>,
    pub name: Option<String>,
    pub tool_call_id: Option<String>,
    pub tool_calls: Option<Vec<InferenceToolCall>>,
    pub images: Vec<InferenceImage>,
    /// Preserves multipart text when attachment references existed but could not load.
    pub has_attachments: bool,
    pub provider_metadata: HashMap<String, String>,
    pub reasoning_history: Option<InferenceReasoningHistory>,
}

/// Tool schema is JSON because JSON Schema allows extensible nested values.
#[derive(Clone, Debug, uniffi::Record)]
pub struct InferenceToolDefinition {
    pub name: String,
    pub description: String,
    pub parameters_json: String,
}

/// Explicit completion inputs and compatibility hints.
#[derive(Clone, Debug, Default, uniffi::Record)]
pub struct InferenceCompletionInput {
    pub model: String,
    pub messages: Vec<InferenceMessage>,
    pub tools: Option<Vec<InferenceToolDefinition>>,
    pub reasoning_effort: Option<String>,
    pub prompt_cache_key: Option<String>,
    pub model_family: Option<InferenceModelFamily>,
    pub is_relay: bool,
    pub reasoning_origin: Option<InferenceReasoningOrigin>,
    /// Legacy plain-text stream: no strict finish requirement or tool events.
    pub text_only: bool,
}

/// Successful provider finish outcomes.
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum InferenceFinishReason {
    Stop,
    ToolCalls,
}

/// Ordered provider events consumed by an agent loop.
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum InferenceEvent {
    ContentDelta { text: String },
    ToolCall { call: InferenceToolCall },
    ProviderMetadata { values: HashMap<String, String> },
    ReasoningHistory { history: InferenceReasoningHistory },
    Finished { reason: InferenceFinishReason },
}

/// Provider failures remain distinct from transport and cancellation failures.
#[derive(Clone, Debug, thiserror::Error, uniffi::Error)]
pub enum InferenceError {
    #[error("Invalid provider URL: {url}")]
    InvalidUrl { url: String },
    #[error("Invalid provider data: {reason}")]
    InvalidData { reason: String },
    #[error("HTTP error {status}")]
    Http { status: u16, body: Option<String> },
    #[error("Network error: {reason}")]
    Transport {
        reason: String,
        domain: Option<String>,
        code: Option<i64>,
    },
    #[error("No credits remaining")]
    NoCredits,
    #[error("Relay wallet source unavailable")]
    WalletUnavailable,
    #[error("Relay is not configured")]
    EiginRelayNotConfigured,
    #[error("Inference cancelled")]
    Cancelled,
    #[error("Inference operation already in use")]
    Busy,
    #[error("Response interrupted")]
    Interrupted,
    #[error("Output limit reached")]
    OutputLimit,
    #[error("Response stopped by provider policy")]
    PolicyStop,
    #[error("Provider response exceeds {limit}")]
    LimitExceeded { limit: String },
}

impl From<crate::http::HttpTransportError> for InferenceError {
    fn from(error: crate::http::HttpTransportError) -> Self {
        match error {
            crate::http::HttpTransportError::Cancelled => Self::Cancelled,
            crate::http::HttpTransportError::Busy => Self::Busy,
            crate::http::HttpTransportError::Failed {
                reason,
                domain,
                code,
            } => Self::Transport {
                reason,
                domain,
                code,
            },
        }
    }
}

impl From<serde_json::Error> for InferenceError {
    fn from(error: serde_json::Error) -> Self {
        Self::InvalidData {
            reason: error.to_string(),
        }
    }
}

/// Classifies only model-specific 400/404 errors for host routing recovery.
#[uniffi::export]
pub fn inference_model_not_found(status: u16, body: Option<String>) -> bool {
    if status != 400 && status != 404 {
        return false;
    }
    let Some(body) = body else {
        return false;
    };
    let lower = body.to_lowercase();
    [
        "model_not_found",
        "model not found",
        "no such model",
        "unknown model",
        "invalid model",
        "unsupported model",
    ]
    .iter()
    .any(|hint| lower.contains(hint))
        || (lower.contains("model")
            && ["does not exist", "is not available", "not a valid model"]
                .iter()
                .any(|hint| lower.contains(hint)))
}
