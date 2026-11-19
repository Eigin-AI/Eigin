use crate::{conversation::ConversationMessage, inference::InferenceToolCall};

/// Host execution output; error results retain their ordinary transcript content.
#[derive(Clone, Debug, uniffi::Record)]
pub struct RoundToolResult {
    pub tool_call_id: String,
    pub content: String,
}

/// Completed inference output consumed by turn progression and host transcript delivery.
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum RoundOutcome {
    Reply {
        message: ConversationMessage,
    },
    Empty,
    Tools {
        assistant: ConversationMessage,
        calls: Vec<InferenceToolCall>,
    },
}

/// Incomplete provider output or invalid use of a round handle.
#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error, uniffi::Error)]
pub enum RoundError {
    #[error("Response interrupted")]
    Interrupted,
    #[error("Invalid tool call")]
    InvalidToolCall,
    #[error("Operation is invalid in the current round phase")]
    InvalidPhase,
}
