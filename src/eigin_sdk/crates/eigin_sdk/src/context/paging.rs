use super::ContextMessage;
use super::estimate::{message_cost, message_cost_with_content};
use crate::conversation::{ASSISTANT_ROLE, TOOL_ROLE, USER_ROLE};
use std::collections::BTreeSet;

/// Replacement for an omitted tool-result body.
pub const OMITTED_TOOL_RESULT: &str = "[omitted]";

/// Input-local range which must remain intact and unmasked.
#[derive(Clone, Debug, uniffi::Record)]
pub struct ContextProtectedRange {
    /// Inclusive message index.
    pub start: u64,
    /// Exclusive message index.
    pub end: u64,
}

/// Explicit previous selection; indices refer to the supplied history.
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct ContextPageSelection {
    /// First retained message. Must be a user-turn boundary or zero.
    pub retained_start: u64,
    /// Tool-result bodies already omitted, in ascending order.
    pub masked_result_indices: Vec<u64>,
}

/// Caller-selected budgets, including fixed input overhead.
#[derive(Clone, Debug, uniffi::Record)]
pub struct ContextPagingPolicy {
    /// Reduce when estimated input exceeds this value.
    pub trigger_tokens: i64,
    /// Desired input size after reduction.
    pub target_tokens: i64,
    /// Absolute safe input limit after output reservation.
    pub maximum_tokens: i64,
    /// Completed turns to preserve in addition to the current turn when they fit the hard limit.
    pub minimum_recent_turns: u64,
}

/// Pure paging inputs. System instructions and schemas belong in fixed_input_tokens.
#[derive(Clone, Debug, uniffi::Record)]
pub struct ContextPagingInput {
    /// Conversation history, starting at a user turn; no system messages.
    pub messages: Vec<ContextMessage>,
    /// Previously applied selection, rebased by the host to these messages.
    pub previous: ContextPageSelection,
    /// Trigger, target, and hard input limits.
    pub policy: ContextPagingPolicy,
    /// Cost of system instructions, schemas, and other nonpageable input.
    pub fixed_input_tokens: i64,
    /// Provider-required active groups; the newest user turn is always protected.
    pub protected_ranges: Vec<ContextProtectedRange>,
}

/// Instructions for the host to apply to a copy of its original messages.
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct ContextPagingResult {
    /// Retained suffix and omitted tool bodies.
    pub selection: ContextPageSelection,
    /// Estimated input cost after selection, including fixed overhead.
    pub estimated_tokens: i64,
    /// Whether this call changed the selection.
    pub changed: bool,
}

/// Invalid inputs or protected content that cannot fit the request.
#[derive(Debug, PartialEq, Eq, thiserror::Error, uniffi::Error)]
pub enum ContextPagingError {
    /// Budgets, message roles, or selection ranges are inconsistent.
    #[error("Invalid context paging input")]
    InvalidInput,
    /// Even the smallest valid selection exceeds the safe input limit.
    #[error("Protected context exceeds the safe input budget")]
    ProtectedContentTooLarge,
}

/// Selects older tool-result masks, then whole-turn eviction, without mutable state.
/// The host must supply valid tool pairing and protect provider-required groups.
#[uniffi::export]
pub fn page_context(input: ContextPagingInput) -> Result<ContextPagingResult, ContextPagingError> {
    validate(&input)?;
    let messages = &input.messages;
    let mut start = input.previous.retained_start as usize;
    let mut masks: BTreeSet<u64> = input
        .previous
        .masked_result_indices
        .iter()
        .copied()
        .collect();
    let turns: Vec<usize> = messages
        .iter()
        .enumerate()
        .filter_map(|(i, m)| (i >= start && m.role == USER_ROLE).then_some(i))
        .collect();
    let newest = turns.last().copied().unwrap_or(messages.len());
    let protected = |i: usize| {
        i >= newest
            || input
                .protected_ranges
                .iter()
                .any(|r| r.start <= i as u64 && (i as u64) < r.end)
    };
    // Wide totals permit exact subtraction even when individual estimates saturate.
    let mut costs: Vec<u128> = messages
        .iter()
        .enumerate()
        .map(|(i, m)| {
            if masks.contains(&(i as u64)) {
                masked_cost(m) as u128
            } else {
                message_cost(m) as u128
            }
        })
        .collect();
    let mut tokens = input.fixed_input_tokens as u128 + costs[start..].iter().sum::<u128>();
    if tokens > input.policy.trigger_tokens as u128 {
        let recent_count = usize::try_from(input.policy.minimum_recent_turns).unwrap_or(usize::MAX);
        let recent_start = turns
            .get(turns.len().saturating_sub(1).saturating_sub(recent_count))
            .copied()
            .unwrap_or(newest);
        // Prefer keeping the recent turns; relax that preference only to satisfy the hard limit.
        for preserve_recent in [true, false] {
            if !preserve_recent && tokens <= input.policy.maximum_tokens as u128 {
                break;
            }
            let goal = if preserve_recent {
                input.policy.target_tokens
            } else {
                input.policy.maximum_tokens
            } as u128;
            let boundary = if preserve_recent {
                recent_start
            } else {
                newest
            };
            for (i, message) in messages.iter().enumerate().take(boundary).skip(start) {
                if tokens <= goal {
                    break;
                }
                if message.role != TOOL_ROLE
                    || protected(i)
                    || message.has_reasoning_history
                    || masks.contains(&(i as u64))
                {
                    continue;
                }
                let replacement_cost = masked_cost(message) as u128;
                if replacement_cost < costs[i] {
                    masks.insert(i as u64);
                    tokens -= costs[i] - replacement_cost;
                    costs[i] = replacement_cost;
                }
            }
            for &next in &turns {
                if tokens <= goal {
                    break;
                }
                if next <= start || next > boundary {
                    continue;
                }
                if (start..next).any(protected) {
                    break;
                }
                tokens -= costs[start..next].iter().sum::<u128>();
                start = next;
            }
        }
    }
    if tokens > input.policy.maximum_tokens as u128 {
        return Err(ContextPagingError::ProtectedContentTooLarge);
    }
    masks.retain(|i| *i >= start as u64);
    let selection = ContextPageSelection {
        retained_start: start as u64,
        masked_result_indices: masks.into_iter().collect(),
    };
    Ok(ContextPagingResult {
        changed: selection != input.previous,
        selection,
        estimated_tokens: tokens as i64,
    })
}

fn masked_cost(message: &ContextMessage) -> i64 {
    message_cost_with_content(message, OMITTED_TOOL_RESULT)
}

fn validate(input: &ContextPagingInput) -> Result<(), ContextPagingError> {
    let invalid = ContextPagingError::InvalidInput;
    let p = &input.policy;
    if p.target_tokens <= 0
        || p.target_tokens >= p.trigger_tokens
        || p.trigger_tokens > p.maximum_tokens
        || input.fixed_input_tokens < 0
    {
        return Err(invalid);
    }
    let messages = &input.messages;
    let start = usize::try_from(input.previous.retained_start)
        .map_err(|_| ContextPagingError::InvalidInput)?;
    if start > messages.len()
        || (!messages.is_empty() && (start == messages.len() || messages[start].role != USER_ROLE))
    {
        return Err(invalid);
    }
    if messages.iter().any(|m| {
        !matches!(m.role.as_str(), USER_ROLE | ASSISTANT_ROLE | TOOL_ROLE)
            || m.additional_input_tokens < 0
    }) {
        return Err(invalid);
    }
    for r in &input.protected_ranges {
        if r.start >= r.end || r.end > messages.len() as u64 || r.start < start as u64 {
            return Err(invalid);
        }
    }
    let newest = messages
        .iter()
        .rposition(|m| m.role == USER_ROLE)
        .unwrap_or(messages.len());
    let mut last = None;
    for &i in &input.previous.masked_result_indices {
        if i < start as u64 || i >= messages.len() as u64 || last.is_some_and(|last| i <= last) {
            return Err(invalid);
        }
        let m = &messages[i as usize];
        if m.role != TOOL_ROLE
            || m.has_reasoning_history
            || i >= newest as u64
            || input
                .protected_ranges
                .iter()
                .any(|r| r.start <= i && i < r.end)
        {
            return Err(invalid);
        }
        last = Some(i);
    }
    Ok(())
}
