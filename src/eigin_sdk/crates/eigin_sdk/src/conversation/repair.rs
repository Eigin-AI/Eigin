use super::{
    ConversationMessage,
    equality::{key, same_payload},
};
use crate::inference::InferenceToolCall;
use std::collections::HashSet;

pub(super) const INTERRUPTED: &str = "Tool execution was interrupted. Completion is unknown; do not repeat the action without checking its state.";

pub(super) fn repair(messages: Vec<ConversationMessage>) -> Vec<ConversationMessage> {
    let mut result: Vec<ConversationMessage> = Vec::new();
    let mut i = 0;
    while i < messages.len() {
        let message = &messages[i];
        if let Some(calls) = message
            .tool_calls
            .as_ref()
            .filter(|calls| message.role == "assistant" && !calls.is_empty())
        {
            let expected: HashSet<_> = calls.iter().map(|call| key(&call.id)).collect();
            let mut j = i + 1;
            while j < messages.len() && messages[j].role == "tool" {
                j += 1;
            }
            let found: HashSet<_> = messages[i + 1..j]
                .iter()
                .filter_map(|m| m.tool_call_id.as_deref().map(key))
                .collect();
            if found == expected && !result.last().is_some_and(|m| m.role == "system") {
                result.push(message.clone());
                result.extend(repair_results(&messages[i + 1..j], calls));
            }
            i = j;
        } else {
            if message.role != "tool" {
                result.push(message.clone());
            }
            i += 1;
        }
    }
    result
}

fn repair_results(
    messages: &[ConversationMessage],
    calls: &[InferenceToolCall],
) -> Vec<ConversationMessage> {
    if calls
        .iter()
        .map(|c| key(&c.id))
        .collect::<HashSet<_>>()
        .len()
        != calls.len()
    {
        return messages.to_vec();
    }
    let mut unique = Vec::new();
    for message in messages {
        if !unique
            .iter()
            .any(|existing| same_payload(existing, message))
        {
            unique.push(message.clone());
        }
    }
    unique
        .iter()
        .filter(|message| {
            let Some(call) = calls
                .iter()
                .find(|c| Some(key(&c.id)) == message.tool_call_id.as_deref().map(key))
            else {
                return true;
            };
            !is_placeholder(message, call)
                || unique
                    .iter()
                    .filter(|other| {
                        other.tool_call_id.as_deref().map(key)
                            == message.tool_call_id.as_deref().map(key)
                            && !is_placeholder(other, call)
                    })
                    .count()
                    != 1
        })
        .cloned()
        .collect()
}

fn is_placeholder(message: &ConversationMessage, call: &InferenceToolCall) -> bool {
    message.content.as_deref() == Some(INTERRUPTED)
        && message
            .name
            .as_ref()
            .is_none_or(|name| key(name) == key(&call.name))
        && message.attachments.as_ref().is_none_or(Vec::is_empty)
        && message.tool_calls.as_ref().is_none_or(Vec::is_empty)
        && message
            .provider_metadata
            .as_ref()
            .is_none_or(|m| m.is_empty())
        && message.reasoning_history.is_none()
        && !message.is_compaction_summary
        && message.compaction_retained_message_count.is_none()
}
