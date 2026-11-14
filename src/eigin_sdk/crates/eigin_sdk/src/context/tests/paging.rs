use super::super::paging::*;
use super::super::{ContextMessage, ContextToolCall};

fn message(role: &str, tokens: usize) -> ContextMessage {
    ContextMessage {
        role: role.into(),
        content: Some("x".repeat(tokens * 4)),
        name: None,
        tool_calls: vec![],
        additional_input_tokens: 0,
        has_reasoning_history: false,
    }
}

fn input(messages: Vec<ContextMessage>) -> ContextPagingInput {
    ContextPagingInput {
        messages,
        previous: ContextPageSelection {
            retained_start: 0,
            masked_result_indices: vec![],
        },
        policy: ContextPagingPolicy {
            trigger_tokens: 300,
            target_tokens: 150,
            maximum_tokens: 400,
            minimum_recent_turns: 1,
        },
        fixed_input_tokens: 20,
        protected_ranges: vec![],
    }
}

fn tool_history() -> Vec<ContextMessage> {
    let mut call = message("assistant", 10);
    call.tool_calls.push(ContextToolCall {
        name: "read".into(),
        arguments: "{}".into(),
    });
    vec![
        message("user", 10),
        call,
        message("tool", 300),
        message("assistant", 10),
        message("user", 10),
        message("assistant", 10),
        message("user", 10),
    ]
}

#[test]
fn tool_results_are_masked_before_text_is_evicted() {
    let request = input(tool_history());
    let original = request.messages[2].content.clone();
    let result = page_context(request.clone()).unwrap();
    assert_eq!(result.selection.retained_start, 0);
    assert_eq!(result.selection.masked_result_indices, vec![2]);
    assert!(result.estimated_tokens <= 150);
    assert_eq!(request.messages[2].content, original);
    let replay = page_context(ContextPagingInput {
        previous: result.selection.clone(),
        ..request
    })
    .unwrap();
    assert_eq!(replay.selection, result.selection);
    assert!(!replay.changed);
}

#[test]
fn text_history_drops_whole_old_turns() {
    let result = page_context(input(vec![
        message("user", 100),
        message("assistant", 150),
        message("user", 10),
        message("assistant", 10),
        message("user", 10),
    ]))
    .unwrap();
    assert_eq!(result.selection.retained_start, 2);
    assert!(result.selection.masked_result_indices.is_empty());
}

#[test]
fn unchanged_at_trigger_and_paging_above_it() {
    let mut request = input(vec![
        message("user", 50),
        message("assistant", 50),
        message("user", 10),
    ]);
    // 20 fixed + 3*4 framing + 110 content.
    request.policy.trigger_tokens = 142;
    request.policy.target_tokens = 70;
    request.policy.minimum_recent_turns = 0;
    assert!(!page_context(request.clone()).unwrap().changed);
    request.fixed_input_tokens += 1;
    assert_eq!(page_context(request).unwrap().selection.retained_start, 2);
}

#[test]
fn recent_turn_preference_yields_to_hard_budget() {
    let result = page_context(input(vec![
        message("user", 300),
        message("assistant", 100),
        message("user", 10),
    ]))
    .unwrap();
    assert_eq!(result.selection.retained_start, 2);
}

#[test]
fn protected_content_fails_instead_of_truncating() {
    let mut request = input(tool_history());
    request
        .protected_ranges
        .push(ContextProtectedRange { start: 0, end: 4 });
    assert_eq!(
        page_context(request).unwrap_err(),
        ContextPagingError::ProtectedContentTooLarge
    );
    assert_eq!(
        page_context(input(vec![message("user", 500)])).unwrap_err(),
        ContextPagingError::ProtectedContentTooLarge
    );
}

#[test]
fn reasoning_results_are_not_modified() {
    let mut request = input(tool_history());
    request.messages[2].has_reasoning_history = true;
    let result = page_context(request).unwrap();
    assert_eq!(result.selection.retained_start, 4);
    assert!(result.selection.masked_result_indices.is_empty());
}

#[test]
fn append_and_replay_never_resurrect_content() {
    let mut request = input(tool_history());
    let first = page_context(request.clone()).unwrap();
    request.previous = first.selection.clone();
    request
        .messages
        .extend([message("assistant", 10), message("user", 10)]);
    let next = page_context(request).unwrap();
    assert_eq!(next.selection, first.selection);
    assert!(!next.changed);
}

#[test]
fn rejects_invalid_ranges_and_selections() {
    let base = input(tool_history());
    for (start, end) in [(0, 0), (3, 2), (0, 100), (u64::MAX, u64::MAX)] {
        let mut request = base.clone();
        request.protected_ranges = vec![ContextProtectedRange { start, end }];
        assert_eq!(
            page_context(request).unwrap_err(),
            ContextPagingError::InvalidInput
        );
    }
    for masks in [vec![2, 2], vec![3, 2], vec![0], vec![100]] {
        let mut request = base.clone();
        request.previous.masked_result_indices = masks;
        assert_eq!(
            page_context(request).unwrap_err(),
            ContextPagingError::InvalidInput
        );
    }
    for start in [1, 7, u64::MAX] {
        let mut request = base.clone();
        request.previous.retained_start = start;
        assert_eq!(
            page_context(request).unwrap_err(),
            ContextPagingError::InvalidInput
        );
    }
}

#[test]
fn empty_history_and_fixed_overhead() {
    assert_eq!(page_context(input(vec![])).unwrap().estimated_tokens, 20);
    let mut request = input(vec![]);
    request.fixed_input_tokens = i64::MAX;
    assert_eq!(
        page_context(request).unwrap_err(),
        ContextPagingError::ProtectedContentTooLarge
    );
}

#[test]
fn saturated_costs_do_not_wrap_or_hide_protected_overflow() {
    let mut request = input(vec![
        message("user", 10),
        message("assistant", 10),
        message("user", 10),
    ]);
    request.messages[0].additional_input_tokens = i64::MAX;
    assert_eq!(
        page_context(request.clone())
            .unwrap()
            .selection
            .retained_start,
        2
    );
    request.messages[2].additional_input_tokens = i64::MAX;
    assert_eq!(
        page_context(request).unwrap_err(),
        ContextPagingError::ProtectedContentTooLarge
    );
}

#[test]
fn recent_retention_counts_completed_turns_separately_from_current() {
    let mut request = input(vec![
        message("user", 120),
        message("assistant", 10),
        message("user", 120),
        message("assistant", 10),
        message("user", 30),
    ]);
    request.policy.minimum_recent_turns = 2;
    let result = page_context(request).unwrap();
    assert!(!result.changed);
    assert_eq!(result.selection.retained_start, 0);
}

#[test]
fn hard_limit_fallback_stops_as_soon_as_recent_history_fits() {
    let mut request = input(vec![
        message("user", 96),
        message("user", 97),
        message("user", 196),
        message("user", 96),
    ]);
    request.fixed_input_tokens = 0;
    request.policy.minimum_recent_turns = 2;
    let result = page_context(request).unwrap();
    assert_eq!(result.selection.retained_start, 2);
    assert_eq!(result.estimated_tokens, 300);
}

#[test]
fn many_old_results_are_reduced_in_one_event() {
    let mut messages = Vec::new();
    for _ in 0..2000 {
        messages.extend([
            message("user", 2),
            message("assistant", 2),
            message("tool", 1000),
        ]);
    }
    messages.push(message("user", 10));
    let mut request = input(messages);
    request.policy = ContextPagingPolicy {
        trigger_tokens: 100_000,
        target_tokens: 50_000,
        maximum_tokens: 150_000,
        minimum_recent_turns: 2,
    };
    let result = page_context(request).unwrap();
    assert!(result.estimated_tokens <= 50_000);
    assert!(result.selection.masked_result_indices.len() > 1900);
}
