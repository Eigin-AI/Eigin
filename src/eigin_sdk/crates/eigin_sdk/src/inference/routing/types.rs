use crate::model_catalog::CatalogReasoningControl;

/// Routing facts for an offered model, independent of catalog storage.
#[derive(Clone, Debug, uniffi::Record)]
pub struct RoutingModel {
    pub id: String,
    pub rank: Option<u64>,
    pub supports_tools: bool,
    pub supports_vision: bool,
    pub supports_reasoning: bool,
    pub context_window: i64,
    pub max_output: Option<i64>,
    pub reasoning_control: Option<CatalogReasoningControl>,
}

/// One provider's inventory and resolved model facts. Order and duplicates are retained.
#[derive(Clone, Debug, uniffi::Record)]
pub struct RoutingInventory {
    pub provider_id: String,
    pub base_url: String,
    pub available: Vec<String>,
    pub enabled: Vec<String>,
    pub models: Vec<RoutingModel>,
}

/// Turn constraints before or after prompt preparation.
#[derive(Clone, Copy, Debug, uniffi::Record)]
pub struct RoutingRequirements {
    pub needs_tools: bool,
    pub needs_vision: bool,
    pub prompt_tokens: Option<i64>,
}

/// Host-supplied turn facts; message inspection stays with the host.
#[derive(Clone, Debug, uniffi::Record)]
pub struct RoutingRequest {
    pub provider_id: String,
    pub current_model: String,
    pub automatic: bool,
    pub conversation_id: Option<String>,
    pub message_needs_reasoning: bool,
    pub requirements: RoutingRequirements,
    pub inventory: Option<RoutingInventory>,
}

/// Why an available model is avoided.
#[derive(Clone, Copy, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum RoutingDegradation {
    Errors,
    SlowFirstToken,
    SlowThroughput,
}

/// Observable reason for changing a cloud model.
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum RoutingChange {
    ModelRetired {
        previous: String,
    },
    ModelDegraded {
        previous: String,
        reason: RoutingDegradation,
    },
    SessionReset {
        previous: String,
    },
    SteppedUp {
        previous: String,
    },
}

/// A decision on the request's provider; persistence belongs to the host.
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct RoutingDecision {
    pub model: String,
    pub change: Option<RoutingChange>,
}

/// Failure classification supplied by the host adapter.
#[derive(Clone, Copy, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum RoutingFailure {
    ModelNotFound,
    ProviderOverloaded,
    Offline,
    NotTheModelsFault,
    TimedOut,
    PreAnswerBufferLimit,
}

impl RoutingFailure {
    pub(super) fn blames_model(self) -> bool {
        matches!(
            self,
            Self::ModelNotFound | Self::ProviderOverloaded | Self::TimedOut
        )
    }
}

/// Completion evidence; cancellation changes no health state.
#[derive(Clone, Debug, uniffi::Enum)]
pub enum RoutingResult {
    Succeeded,
    Failed { failure: RoutingFailure },
    Cancelled,
}

/// Measurements use seconds, matching timestamps supplied to router operations.
#[derive(Clone, Debug, uniffi::Record)]
pub struct RoutingOutcome {
    pub provider_id: String,
    pub model: String,
    pub first_token_seconds: Option<f64>,
    pub tokens_per_second: Option<f64>,
    pub result: RoutingResult,
}

/// Remote evidence, expressed in host wall-clock seconds since the Unix epoch.
#[derive(Clone, Debug, uniffi::Record)]
pub struct RoutingHealthSample {
    pub value: f64,
    pub observed_at: f64,
    pub expires_at: f64,
    pub count: u64,
    pub probe: bool,
}

/// Remote measurements; TTFT values are milliseconds and throughput is tokens/s.
#[derive(Clone, Debug, uniffi::Record)]
pub struct RoutingRemoteHealth {
    pub model: String,
    pub ttft: Vec<RoutingHealthSample>,
    pub tps: Vec<RoutingHealthSample>,
    pub failures: Vec<RoutingHealthSample>,
}
