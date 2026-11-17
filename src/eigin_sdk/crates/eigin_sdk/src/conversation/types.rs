use crate::inference::{InferenceReasoningHistory, InferenceToolCall};
use std::collections::HashMap;

/// Unresolved attachment reference; storage and byte loading belong to the host.
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct ConversationAttachmentReference {
    pub id: String,
    pub kind: String,
    pub mime_type: String,
    pub width: Option<i64>,
    pub height: Option<i64>,
    pub byte_count: i64,
}

/// Conversation values used before attachment resolution and provider encoding.
#[derive(Clone, Debug, Default, PartialEq, Eq, uniffi::Record)]
pub struct ConversationMessage {
    /// Index in the history snapshot; selection assigns it before removing entries.
    pub source_index: Option<u64>,
    pub role: String,
    pub content: Option<String>,
    pub name: Option<String>,
    pub tool_call_id: Option<String>,
    pub tool_calls: Option<Vec<InferenceToolCall>>,
    pub attachments: Option<Vec<ConversationAttachmentReference>>,
    pub provider_metadata: Option<HashMap<String, String>>,
    pub reasoning_history: Option<InferenceReasoningHistory>,
    pub is_compaction_summary: bool,
    pub compaction_retained_message_count: Option<i64>,
}

impl ConversationMessage {
    pub(super) fn text(role: &str, content: String) -> Self {
        Self {
            role: role.into(),
            content: Some(content),
            ..Self::default()
        }
    }
}

/// Active history and the latest summary, ready for host hint gathering.
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct SelectedConversation {
    pub summary: Option<String>,
    pub messages: Vec<ConversationMessage>,
}

/// Finished prompt content and model capabilities supplied by the caller.
#[derive(Clone, Debug, uniffi::Record)]
pub struct ConversationPreparationOptions {
    pub system_prompt: String,
    pub system_hint: Option<String>,
    pub supports_vision: bool,
}

/// Provenance for mapping request-only messages back to host values.
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum PreparedConversationOrigin {
    History {
        source_index: u64,
    },
    /// A caller-created message without history provenance.
    Supplied,
    System,
    Summary,
    SummaryAcknowledgement,
    HintFallback,
}

/// Fully prepared content with explicit provenance for host adaptation.
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct PreparedConversationMessage {
    pub origin: PreparedConversationOrigin,
    pub message: ConversationMessage,
}

/// Invalid history facts that prevent safe conversation selection.
#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error, uniffi::Error)]
pub enum ConversationPreparationError {
    /// A summary cannot retain a negative number of messages.
    #[error("Negative retained-message count at history index {source_index}")]
    InvalidRetainedCount { source_index: u64 },
}

pub(super) fn synthetic(
    origin: PreparedConversationOrigin,
    role: &str,
    content: String,
) -> PreparedConversationMessage {
    PreparedConversationMessage {
        origin,
        message: ConversationMessage::text(role, content),
    }
}

pub(super) fn append_text(message: &mut ConversationMessage, text: &str) {
    let content = message.content.get_or_insert_default();
    if !content.is_empty() {
        content.push_str("\n\n");
    }
    content.push_str(text);
}
