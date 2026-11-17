use crate::conversation::*;
use crate::inference::InferenceToolCall;

pub(super) const ACKNOWLEDGEMENT: &str = "Understood — continuing from there.";
pub(super) const VISION_UNSUPPORTED: &str =
    "[an image was attached here, but this model cannot view images]";
pub(super) const INTERRUPTED: &str = "Tool execution was interrupted. Completion is unknown; do not repeat the action without checking its state.";

pub(super) fn text(role: &str, content: &str) -> ConversationMessage {
    ConversationMessage {
        role: role.into(),
        content: Some(content.into()),
        ..Default::default()
    }
}
pub(super) fn summary(content: &str, retained: i64) -> ConversationMessage {
    ConversationMessage {
        is_compaction_summary: true,
        compaction_retained_message_count: Some(retained),
        ..text("system", content)
    }
}
pub(super) fn call(ids: &[&str]) -> ConversationMessage {
    ConversationMessage {
        tool_calls: Some(
            ids.iter()
                .map(|id| InferenceToolCall {
                    id: (*id).into(),
                    kind: "function".into(),
                    name: "lookup".into(),
                    arguments: "{}".into(),
                })
                .collect(),
        ),
        ..text("assistant", "")
    }
}
pub(super) fn tool(id: &str, content: &str) -> ConversationMessage {
    ConversationMessage {
        tool_call_id: Some(id.into()),
        ..text("tool", content)
    }
}
pub(super) fn image(role: &str, content: &str) -> ConversationMessage {
    ConversationMessage {
        attachments: Some(vec![ConversationAttachmentReference {
            id: content.into(),
            kind: "image".into(),
            mime_type: "image/png".into(),
            width: Some(42),
            height: None,
            byte_count: 100,
        }]),
        ..text(role, content)
    }
}
pub(super) fn options(vision: bool, hint: Option<&str>) -> ConversationPreparationOptions {
    ConversationPreparationOptions {
        system_prompt: "instructions".into(),
        system_hint: hint.map(str::to_owned),
        supports_vision: vision,
    }
}
pub(super) fn prepare(
    history: Vec<ConversationMessage>,
    vision: bool,
    hint: Option<&str>,
) -> Vec<PreparedConversationMessage> {
    conversation_prepare(conversation_select(history).unwrap(), options(vision, hint))
}
pub(super) fn contents(messages: &[PreparedConversationMessage]) -> Vec<&str> {
    messages
        .iter()
        .map(|m| m.message.content.as_deref().unwrap_or(""))
        .collect()
}
