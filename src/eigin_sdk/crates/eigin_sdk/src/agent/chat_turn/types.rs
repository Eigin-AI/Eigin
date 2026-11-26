use super::InlineTurnTools;
use crate::{
    agent::{RoundError, TurnContinuation, TurnError, TurnFailure, TurnOutputEntry, TurnSignals},
    conversation::ConversationMessage,
    inference::{
        InferenceEvent, InferenceToolCall, InferenceToolDefinition,
        local::LocalToolResult,
        request_driver::{RequestError, RequestPlatform},
        routing::RoutingRequest,
    },
};
use futures_util::future::BoxFuture;
use std::sync::Arc;

/// Initial context and lifecycle policy for one complete chat turn.
#[derive(Clone, uniffi::Record)]
pub struct ChatTurnInput {
    pub messages: Vec<ConversationMessage>,
    pub tools: Option<Vec<InferenceToolDefinition>>,
    pub model: String,
    pub initial_instruction: Option<String>,
    pub allow_interruption_recovery: bool,
    pub propagate_stream_cancellation: bool,
}

/// Current SDK-owned context with provenance preserved for host paging and persistence.
#[derive(Clone, uniffi::Record)]
pub struct TurnContext {
    pub initial_messages: Vec<ConversationMessage>,
    pub output: Vec<TurnOutputEntry>,
    pub tools: Option<Vec<InferenceToolDefinition>>,
    pub model: String,
    pub initial_instruction: Option<String>,
    pub continuation: Option<TurnContinuation>,
}

/// Prepared request capabilities; the SDK still selects and consumes candidate attempts.
pub struct PreparedTurnRequest {
    pub provider_id: String,
    pub local: bool,
    pub routing: Option<RoutingRequest>,
    pub platform: Arc<dyn RequestPlatform>,
}

/// Ordered observations of accepted turn progress.
#[derive(Clone, Debug, uniffi::Enum)]
pub enum ChatTurnEvent {
    RequestOpened,
    Finished,
    RequestReported {
        report: Option<crate::inference::request_driver::RequestReport>,
        result: crate::inference::routing::RoutingResult,
    },
    Draft {
        id: u64,
    },
    ModelSelected {
        model: String,
        retry: bool,
    },
    Inference {
        event: InferenceEvent,
    },
    Output {
        entries: Vec<TurnOutputEntry>,
    },
}

/// Awaited presentation work at SDK-owned execution boundaries.
#[derive(Clone, Debug, uniffi::Enum)]
pub enum TurnPresentation {
    /// Ends the prose segment and prepares presentation for a cloud tool batch.
    FinishToolProse {
        has_prose: bool,
    },
    BeforeTool {
        call: InferenceToolCall,
    },
    AfterTool,
    /// Waits for pending presentation to finish before completion or recovery.
    Drain,
}

/// Sampling order differs between failure handling and completed-round checks.
#[derive(Clone, Copy, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum TurnSignalBoundary {
    Failure,
    EmptyReply,
    ToolsCompleted,
}

/// Host context, presentation, and tool capabilities for a complete turn.
/// Dropping a pending callback must release its wait without blocking stop.
pub trait ChatTurnHost: Send + Sync {
    fn prepare(
        &self,
        context: TurnContext,
        inline: Arc<InlineTurnTools>,
    ) -> BoxFuture<'_, Result<PreparedTurnRequest, RequestError>>;
    fn notify(&self, _event: ChatTurnEvent) -> BoxFuture<'_, ()> {
        Box::pin(async {})
    }
    fn present(&self, _work: TurnPresentation) -> BoxFuture<'_, ()> {
        Box::pin(async {})
    }
    fn execute(&self, call: InferenceToolCall) -> BoxFuture<'_, LocalToolResult>;
    fn refresh_tools(&self) -> BoxFuture<'_, Option<Vec<InferenceToolDefinition>>>;
    fn signals(&self, boundary: TurnSignalBoundary) -> BoxFuture<'_, TurnSignals>;
    /// Preserves provider-specific host error classification independently of routing.
    fn classify_failure(&self, error: &RequestError) -> TurnFailure;
}

/// A failed turn retains its checkpoint and the original request error.
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum ChatTurnError {
    #[error(transparent)]
    Request(#[from] RequestError),
    #[error(transparent)]
    Round(#[from] RoundError),
    #[error(transparent)]
    Policy(#[from] TurnError),
    #[error("Response contains no reply")]
    MissingReply,
    #[error("Turn was cancelled")]
    Cancelled,
    #[error("Turn was stopped")]
    Stopped,
    #[error("Turn has already started")]
    AlreadyStarted,
}
