use crate::conversation::{ConversationMessage, INTERRUPTED_TOOL_CONTENT, checkpoint_id_key};
use std::collections::HashSet;

/// Host progress in the supplied produced-message snapshot.
#[derive(Clone, Debug, Default, uniffi::Record)]
pub struct CheckpointProgress {
    /// Safe-to-retain prefix, including batches whose execution is incomplete.
    pub retained_count: u64,
    pub is_done: bool,
    pub is_executing_tools: bool,
    pub partial_content: String,
    /// Position of the current prose message, resolved from host identity.
    pub current_message_index: Option<u64>,
}

/// Provenance for restoring host identities without exposing them to the SDK.
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum CheckpointOrigin {
    Produced { index: u64 },
    InterruptedTool,
    PartialProse,
}

/// A retained or synthesized checkpoint value.
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct CheckpointMessage {
    pub message: ConversationMessage,
    pub origin: CheckpointOrigin,
}

/// Builds an observational snapshot; the host owns timing, persistence, and execution.
#[uniffi::export]
pub fn agent_build_checkpoint(
    produced: Vec<ConversationMessage>,
    progress: CheckpointProgress,
) -> Vec<CheckpointMessage> {
    let count = if progress.is_done {
        produced.len()
    } else {
        usize::try_from(progress.retained_count)
            .unwrap_or(usize::MAX)
            .min(produced.len())
    };
    let mut result: Vec<_> = produced
        .into_iter()
        .take(count)
        .enumerate()
        .map(|(index, message)| CheckpointMessage {
            message,
            origin: CheckpointOrigin::Produced {
                index: index as u64,
            },
        })
        .collect();
    if progress.is_done {
        return result;
    }

    if let Some(calls) = result.iter().rev().find_map(|entry| {
        entry
            .message
            .tool_calls
            .as_ref()
            .filter(|calls| !calls.is_empty())
    }) {
        // Match against the whole retained snapshot, preserving the host's ID semantics.
        let completed: HashSet<_> = result
            .iter()
            .filter_map(|entry| entry.message.tool_call_id.as_deref().map(checkpoint_id_key))
            .collect();
        let missing: Vec<_> = calls
            .iter()
            .filter(|call| !completed.contains(&checkpoint_id_key(&call.id)))
            .map(|call| CheckpointMessage {
                message: ConversationMessage {
                    role: "tool".into(),
                    content: Some(INTERRUPTED_TOOL_CONTENT.into()),
                    tool_call_id: Some(call.id.clone()),
                    name: Some(call.name.clone()),
                    ..Default::default()
                },
                origin: CheckpointOrigin::InterruptedTool,
            })
            .collect();
        result.extend(missing);
    }
    if !progress.partial_content.is_empty()
        && !progress.is_executing_tools
        && !progress
            .current_message_index
            .is_some_and(|index| index < count as u64)
    {
        result.push(CheckpointMessage {
            message: ConversationMessage {
                role: "assistant".into(),
                content: Some(progress.partial_content),
                ..Default::default()
            },
            origin: CheckpointOrigin::PartialProse,
        });
    }
    result
}
