use super::ContextMessage;
use super::estimate::{message_cost, messages_cost};
use unicode_segmentation::UnicodeSegmentation;

/// A contiguous suffix, optionally replacing its first message's content.
#[derive(Debug, PartialEq, Eq, uniffi::Record)]
pub struct ContextSelection {
    /// Start of the suffix; message count denotes an empty selection.
    pub start_index: u64,
    /// Replacement content for the first selected message, when truncated.
    pub partial_content: Option<String>,
}

fn suffix(start: usize) -> ContextSelection {
    ContextSelection {
        start_index: start as u64,
        partial_content: None,
    }
}

/// Keeps whole newest user turns, honoring the minimum even beyond the budget.
/// Stops before a user message beginning with the summary carrier tag.
#[uniffi::export]
pub fn retained_tail(
    messages: Vec<ContextMessage>,
    token_budget: i64,
    minimum_turns: i64,
) -> ContextSelection {
    let mut start = messages.len();
    let mut budget = token_budget;
    let mut turns = 0_i64;
    let mut scan = messages.len();
    while let Some(turn_start) = messages[..scan]
        .iter()
        .rposition(|message| message.role == "user")
    {
        if messages[turn_start]
            .content
            .as_deref()
            .is_some_and(|text| text.starts_with("<conversation_summary>"))
        {
            break;
        }
        let cost = messages_cost(&messages[turn_start..scan]);
        if turns >= minimum_turns && cost > budget {
            break;
        }
        budget = budget.saturating_sub(cost);
        turns = turns.saturating_add(1);
        start = turn_start;
        scan = turn_start;
    }
    suffix(start)
}

/// Keeps the newest suffix, optionally truncating its first message's content.
/// The partial content allowance subtracts message framing and excludes tool/name costs.
#[uniffi::export]
pub fn truncate_for_budget(messages: Vec<ContextMessage>, token_budget: i64) -> ContextSelection {
    let mut accumulated = 0_i64;
    let mut start = messages.len();
    for i in (0..messages.len()).rev() {
        let cost = message_cost(&messages[i]);
        if accumulated.saturating_add(cost) > token_budget {
            let remaining = token_budget.saturating_sub(accumulated).saturating_sub(4);
            if i + 1 == start && remaining > 20 && !messages[i].has_reasoning_history {
                let content = messages[i].content.as_deref().unwrap_or("");
                let max_chars = usize::try_from(remaining.saturating_mul(4)).unwrap_or(usize::MAX);
                let graphemes: Vec<_> = content.graphemes(true).collect();
                let partial = if graphemes.len() > max_chars {
                    format!(
                        "…{}",
                        graphemes[graphemes.len() - (max_chars - 1)..].concat()
                    )
                } else {
                    content.to_owned()
                };
                return ContextSelection {
                    start_index: i as u64,
                    partial_content: Some(partial),
                };
            }
            break;
        }
        accumulated = accumulated.saturating_add(cost);
        start = i;
    }
    suffix(start)
}

/// Selects a whole-message suffix using a quantized hysteresis threshold.
/// Always retains the newest message when present, even beyond the high mark.
#[uniffi::export]
pub fn windowed_for_budget(
    messages: Vec<ContextMessage>,
    high_mark: i64,
    low_mark: i64,
) -> ContextSelection {
    if messages.is_empty() {
        return suffix(0);
    }
    if high_mark <= 0 {
        return suffix(messages.len() - 1);
    }
    let mut cumulative = vec![0_i64];
    for message in &messages {
        cumulative.push(
            cumulative
                .last()
                .unwrap()
                .saturating_add(message_cost(message)),
        );
    }
    let total = *cumulative.last().unwrap();
    if total <= high_mark {
        return suffix(0);
    }
    let low = low_mark.clamp(0, high_mark - 1);
    let step = high_mark - low;
    let threshold = ((total - low) / step) * step;
    let start = cumulative
        .iter()
        .position(|cost| *cost >= threshold)
        .unwrap_or(messages.len());
    suffix(start.min(messages.len() - 1))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::context::{ContextToolCall, estimate_messages};

    fn message(role: &str, tokens: usize) -> ContextMessage {
        ContextMessage {
            role: role.into(),
            content: Some("x".repeat(tokens.saturating_sub(4) * 4)),
            name: None,
            tool_calls: vec![],
            additional_input_tokens: 0,
            has_reasoning_history: false,
        }
    }

    #[test]
    fn retained_turns_minimum_boundaries_and_tools() {
        let mut messages = vec![
            message("system", 5),
            message("user", 10),
            message("assistant", 10),
            message("user", 1000),
            message("user", 10),
            message("assistant", 5),
            message("tool", 10),
            message("assistant", 10),
            message("user", 10),
            message("assistant", 10),
        ];
        messages[5].tool_calls.push(ContextToolCall {
            name: "test".into(),
            arguments: "{}".into(),
        });
        assert_eq!(retained_tail(messages.clone(), 100, 2).start_index, 4);
        assert_eq!(retained_tail(messages.clone(), -1, 2).start_index, 4);
        assert_eq!(retained_tail(messages.clone(), 100_000, 2).start_index, 1);
        messages[3].content = Some("<conversation_summary>old".into());
        assert_eq!(retained_tail(messages, 100_000, 2).start_index, 4);
        assert_eq!(
            retained_tail(vec![message("assistant", 10)], 100, 2).start_index,
            1
        );
        assert_eq!(retained_tail(vec![], 100, 2).start_index, 0);
        let turns = vec![message("user", 10); 10];
        assert_eq!(retained_tail(turns.clone(), 50, 2).start_index, 5);
        assert_eq!(retained_tail(turns, 0, 0).start_index, 10);
    }

    #[test]
    fn retained_tail_extends_with_short_whole_turns() {
        let messages: Vec<_> = (0..10)
            .flat_map(|_| [message("user", 10), message("assistant", 10)])
            .collect();
        assert_eq!(retained_tail(messages.clone(), 100_000, 2).start_index, 0);
        let selection = retained_tail(messages.clone(), 100, 2);
        assert_eq!(selection.start_index, 10);
        assert!(selection.partial_content.is_none());
        assert_eq!(messages[selection.start_index as usize].role, "user");
        assert_eq!(
            messages_cost(&messages[selection.start_index as usize..]),
            100
        );
    }

    #[test]
    fn truncation_preserves_suffix_and_partial_graphemes() {
        let messages = vec![message("user", 29); 5];
        assert_eq!(truncate_for_budget(messages.clone(), 60).start_index, 3);
        assert_eq!(
            truncate_for_budget(messages.clone(), 100_000).start_index,
            0
        );
        assert_eq!(truncate_for_budget(messages.clone(), 0).start_index, 5);
        assert_eq!(truncate_for_budget(messages, i64::MIN).start_index, 5);
        assert_eq!(truncate_for_budget(vec![], 100).start_index, 0);
        let mut msg = message("user", 1000);
        msg.content = Some("👨‍👩‍👧‍👦".repeat(400));
        let result = truncate_for_budget(vec![msg.clone(), message("assistant", 5)], 35);
        assert_eq!(result.start_index, 0);
        assert_eq!(
            result.partial_content,
            Some(format!("…{}", "👨‍👩‍👧‍👦".repeat(103)))
        );
        msg.has_reasoning_history = true;
        assert_eq!(truncate_for_budget(vec![msg], 35).start_index, 1);
        assert!(
            truncate_for_budget(vec![message("user", 1000)], 24)
                .partial_content
                .is_none()
        );
    }

    #[test]
    fn partial_allowance_excludes_tool_overhead() {
        let mut msg = message("assistant", 1000);
        msg.tool_calls.push(ContextToolCall {
            name: "test".into(),
            arguments: "x".repeat(400),
        });
        let selection = truncate_for_budget(vec![msg.clone()], 30);
        msg.content = selection.partial_content;
        assert!(estimate_messages(vec![msg]) > 30);
    }

    #[test]
    fn window_hysteresis_suffix_and_exceptions() {
        assert_eq!(windowed_for_budget(vec![], 1000, 500).start_index, 0);
        for n in 1..=60 {
            let messages = vec![message("user", 100); n];
            let start = windowed_for_budget(messages.clone(), 1000, 500).start_index as usize;
            assert!(start < n);
            assert!((n - start) * 100 <= 1000);
            let expected = if n <= 10 { 0 } else { ((n - 5) / 5) * 5 };
            assert_eq!(start, expected);
            assert_eq!(
                windowed_for_budget(messages, 0, 500).start_index as usize,
                n - 1
            );
        }
        assert_eq!(
            windowed_for_budget(vec![message("user", 50), message("user", 5000)], 1000, 500)
                .start_index,
            1
        );
        for (low, expected_start) in [(-1, 19), (1000, 11), (i64::MAX, 11)] {
            assert_eq!(
                windowed_for_budget(vec![message("user", 100); 20], 1000, low).start_index,
                expected_start
            );
        }
    }

    #[test]
    fn extreme_costs_saturate_without_panicking() {
        let mut msg = message("assistant", 5);
        msg.additional_input_tokens = i64::MAX;
        assert_eq!(estimate_messages(vec![msg.clone(); 2]), i64::MAX);
        for high in [1, 100, i64::MAX - 1, i64::MAX] {
            for low in [i64::MIN, 0, 1, 50, i64::MAX - 2, i64::MAX] {
                windowed_for_budget(vec![msg.clone(); 2], high, low);
            }
        }
        assert_eq!(
            truncate_for_budget(vec![message("user", 5)], i64::MAX).start_index,
            0
        );
        truncate_for_budget(vec![msg.clone(); 2], i64::MAX - 1);
        truncate_for_budget(vec![msg.clone(); 2], i64::MIN);
        retained_tail(vec![msg; 2], i64::MIN, i64::MAX);
    }
}
