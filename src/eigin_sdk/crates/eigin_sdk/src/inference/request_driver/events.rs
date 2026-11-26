use super::RequestError;
use crate::inference::{AttemptEvent, InferenceEvent, InferenceFinishReason};

pub(super) fn classify(event: &InferenceEvent) -> AttemptEvent {
    match event {
        InferenceEvent::ContentDelta { text } => AttemptEvent::Content {
            nonempty: !text.is_empty(),
        },
        InferenceEvent::ToolCall { call } => AttemptEvent::ToolCall {
            has_id: !call.id.is_empty(),
            has_name: !call.name.is_empty(),
            object_arguments: crate::agent::arguments::valid_object(&call.arguments),
        },
        _ => AttemptEvent::Ancillary,
    }
}

// Preserve the host's memory estimate, including its fixed per-event overhead.
pub(super) fn buffered_bytes(event: &InferenceEvent) -> u64 {
    let bytes = match event {
        InferenceEvent::ContentDelta { text } => text.len() + 64,
        InferenceEvent::ToolCall { call } => {
            call.id.len() + call.name.len() + call.arguments.len() + 64
        }
        InferenceEvent::ProviderMetadata { values } => values
            .iter()
            .fold(64, |size, (key, value)| size + key.len() + value.len() + 64),
        InferenceEvent::ReasoningHistory { history } => {
            history.payload.len()
                + history.visible_text.len()
                + history.format.len()
                + history.origin.endpoint.len()
                + history.origin.model.len()
                + 128
        }
        InferenceEvent::Performance { .. } | InferenceEvent::Finished { .. } => 64,
    };
    bytes as u64
}

pub(super) fn unusable(events: &[InferenceEvent]) -> RequestError {
    let finished = |reason| events.contains(&InferenceEvent::Finished { reason });
    if finished(InferenceFinishReason::ToolCalls)
        && events
            .iter()
            .any(|event| matches!(event, InferenceEvent::ToolCall { .. }))
    {
        RequestError::InvalidToolCall
    } else if finished(InferenceFinishReason::Stop) {
        RequestError::MissingReply
    } else {
        RequestError::Inference(crate::inference::InferenceError::Interrupted)
    }
}
