use super::ContextMessage;
use super::estimate::messages_cost;

/// Estimates serialized tool definitions, including schema bytes and per-tool framing.
#[uniffi::export]
pub fn estimate_serialized_tools(serialized_tools: String, tool_count: u64) -> i64 {
    if tool_count == 0 {
        return 0;
    }
    let schema_cost = i64::try_from(serialized_tools.len() / 3).unwrap_or(i64::MAX);
    let framing = i64::try_from(tool_count)
        .unwrap_or(i64::MAX)
        .saturating_mul(32);
    schema_cost.saturating_add(1).saturating_add(framing)
}

/// Estimates messages and serialized tool definitions with saturating arithmetic.
#[uniffi::export]
pub fn estimate_request_with_tools(
    messages: Vec<ContextMessage>,
    serialized_tools: String,
    tool_count: u64,
) -> i64 {
    messages_cost(&messages).saturating_add(estimate_serialized_tools(serialized_tools, tool_count))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn serialized_schema_growth_changes_request_budget() {
        let small = estimate_request_with_tools(vec![], "[]".into(), 1);
        let large = estimate_request_with_tools(vec![], "schema".repeat(1000), 1);
        assert!(large > small);
        assert_eq!(estimate_serialized_tools("[]".into(), 0), 0);
        assert_eq!(estimate_serialized_tools("[]".into(), u64::MAX), i64::MAX);
    }

    #[test]
    fn combined_request_saturates() {
        let message = ContextMessage {
            role: "user".into(),
            content: Some("hello".into()),
            name: None,
            tool_calls: vec![],
            additional_input_tokens: i64::MAX,
            has_reasoning_history: false,
        };
        assert_eq!(
            estimate_request_with_tools(vec![message], "schema".into(), 1),
            i64::MAX
        );
    }
}
