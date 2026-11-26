use crate::{
    inference::{InferenceError, InferenceEvent, routing::RoutingFailure},
    model_catalog::CatalogReasoningEffort,
};
use futures_util::future::BoxFuture;
use std::sync::Arc;

/// Failures surfaced by a prepared inference request.
#[derive(Clone, Debug, thiserror::Error, uniffi::Error)]
pub enum RequestError {
    #[error(transparent)]
    Inference(#[from] InferenceError),
    /// Adapter classification preserves provider-specific routing behavior.
    #[error("{error}")]
    Classified {
        error: InferenceError,
        failure: RoutingFailure,
    },
    /// Request-scoped identity lets the host restore its original presentation error.
    #[error("{message}")]
    Host {
        id: String,
        message: String,
        failure: RoutingFailure,
    },
    #[error("No candidate produced useful output before the deadline")]
    FirstEventTimeout,
    #[error("Stream ended without useful output")]
    NoUsefulOutput,
    #[error("Candidate exceeded its pre-answer event buffer")]
    BufferOverflow,
    #[error("Response contains an invalid tool call")]
    InvalidToolCall,
    #[error("Response contains no reply")]
    MissingReply,
}

impl RequestError {
    pub(super) fn cancelled(&self) -> bool {
        matches!(
            self,
            Self::Inference(InferenceError::Cancelled)
                | Self::Classified {
                    error: InferenceError::Cancelled,
                    ..
                }
        )
    }

    pub(super) fn missing_model(&self) -> bool {
        self.routing_failure() == RoutingFailure::ModelNotFound
    }

    /// Uses explicit provider classification; unclassified failures do not blame a model.
    pub fn routing_failure(&self) -> RoutingFailure {
        match self {
            Self::Classified { failure, .. } | Self::Host { failure, .. } => *failure,
            Self::FirstEventTimeout => RoutingFailure::TimedOut,
            Self::BufferOverflow => RoutingFailure::PreAnswerBufferLimit,
            _ => RoutingFailure::NotTheModelsFault,
        }
    }
}

/// An opened candidate. Cancelling must wake pending reads and stop provider work.
pub trait RequestCandidate: Send + Sync {
    fn next(&self) -> BoxFuture<'_, Result<Option<InferenceEvent>, RequestError>>;
    fn cancel(&self);
}

/// Effects used by the request coordinator. Routing implementations can use the SDK router.
/// Dropping a pending effect must cancel its work. Preparation does not dispatch inference.
pub trait RequestEffects: Send + Sync {
    /// Delivers terminal timing even after cancellation, without admitting output.
    fn reported(
        &self,
        report: Option<crate::inference::request_driver::RequestReport>,
        result: crate::inference::routing::RoutingResult,
    ) {
        let _ = (report, result);
    }

    /// Revokes request-scoped callbacks before terminal cleanup can reenter the host.
    /// May be called repeatedly; losing a candidate alone does not close the request.
    fn close(&self) {}
    fn prepare(
        &self,
        id: u64,
        model: String,
    ) -> BoxFuture<'_, Result<Option<CatalogReasoningEffort>, RequestError>>;
    fn open(
        &self,
        id: u64,
        model: String,
        effort: Option<CatalogReasoningEffort>,
    ) -> BoxFuture<'_, Result<Arc<dyn RequestCandidate>, RequestError>>;
    /// Cancels preparation or opening for this candidate; repeated calls are harmless.
    fn cancel(&self, id: u64);
    /// Records routing health synchronously, including failures reported during cancellation.
    fn record_failure(&self, model: String, error: RequestError);
    fn refresh_catalog(&self) -> BoxFuture<'_, ()>;
    fn rank_replacement(&self, model: String, error: RequestError)
    -> BoxFuture<'_, Option<String>>;
    fn record_loser(&self, model: String, silent_ms: u64);
    fn record_outcome(&self, report: super::RequestReport);
}

/// Inputs for one prepared request. Local requests bypass the useful-output race.
#[derive(Clone, Debug)]
pub struct RequestOptions {
    pub model: String,
    pub local: bool,
    pub routed: bool,
    pub hedge: Option<RequestHedge>,
    pub ceiling_ms: u32,
    pub max_buffered_bytes: u64,
}

/// A candidate dispatched after the primary remains silent for the given interval.
#[derive(Clone, Debug)]
pub struct RequestHedge {
    pub model: String,
    pub delay_ms: u32,
}
