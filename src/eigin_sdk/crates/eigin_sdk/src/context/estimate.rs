use unicode_segmentation::UnicodeSegmentation;

/// Tool-call fields included in the context estimate.
#[derive(Clone, Debug, uniffi::Record)]
pub struct ContextToolCall {
    /// Function name.
    pub name: String,
    /// Serialized function arguments.
    pub arguments: String,
}

/// Message information needed for context decisions.
#[derive(Clone, Debug, uniffi::Record)]
pub struct ContextMessage {
    /// API role; user messages delimit turns.
    pub role: String,
    /// Visible message content.
    pub content: Option<String>,
    /// Optional sender name.
    pub name: Option<String>,
    /// Calls included in this message.
    pub tool_calls: Vec<ContextToolCall>,
    /// Host-validated reasoning token contribution.
    pub additional_input_tokens: i64,
    /// Whether any reasoning history exists, including invalid history.
    pub has_reasoning_history: bool,
}

/// Estimates text using extended grapheme clusters, with a minimum of one token.
#[uniffi::export]
pub fn estimate_text(text: String) -> i64 {
    text_cost(&text)
}

fn text_cost(text: &str) -> i64 {
    i64::try_from(text.graphemes(true).count() / 4)
        .unwrap_or(i64::MAX)
        .max(1)
}

pub(super) fn message_cost(message: &ContextMessage) -> i64 {
    let mut cost = 4_i64
        .saturating_add(text_cost(message.content.as_deref().unwrap_or("")))
        .saturating_add(message.additional_input_tokens);
    for call in &message.tool_calls {
        cost = cost
            .saturating_add(10)
            .saturating_add(text_cost(&call.name))
            .saturating_add(text_cost(&call.arguments));
    }
    if let Some(name) = &message.name {
        cost = cost.saturating_add(text_cost(name));
    }
    cost
}

pub(super) fn messages_cost(messages: &[ContextMessage]) -> i64 {
    messages.iter().fold(0_i64, |sum, message| {
        sum.saturating_add(message_cost(message))
    })
}

/// Estimates messages, including framing, tool calls, and validated reasoning.
/// Arithmetic saturates at signed 64-bit limits.
#[uniffi::export]
pub fn estimate_messages(messages: Vec<ContextMessage>) -> i64 {
    messages_cost(&messages)
}

/// Estimates tool schemas at 150 tokens per definition, saturating on overflow.
#[uniffi::export]
pub fn estimate_tools(tool_count: u64) -> i64 {
    i64::try_from(tool_count)
        .unwrap_or(i64::MAX)
        .saturating_mul(150)
}

/// Estimates messages and tool definitions, saturating on overflow.
#[uniffi::export]
pub fn estimate_request(messages: Vec<ContextMessage>, tool_count: u64) -> i64 {
    messages_cost(&messages).saturating_add(estimate_tools(tool_count))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn estimates_graphemes_and_empty_content() {
        for grapheme in ["x", "e\u{301}", "👨‍👩‍👧‍👦", "🇩🇰", "👍🏽", "\r\n"]
        {
            assert_eq!(estimate_text(grapheme.repeat(12)), 3);
        }
        assert_eq!(estimate_text(String::new()), 1);
        let mut msg = ContextMessage {
            role: "assistant".into(),
            content: None,
            name: Some("name".into()),
            tool_calls: vec![],
            additional_input_tokens: 0,
            has_reasoning_history: false,
        };
        msg.tool_calls.push(ContextToolCall {
            name: "test".into(),
            arguments: "{}".into(),
        });
        msg.additional_input_tokens = 17;
        assert_eq!(estimate_messages(vec![msg.clone()]), 35);
        assert_eq!(estimate_request(vec![msg], 2), 335);
        assert_eq!(estimate_tools(u64::MAX), i64::MAX);
    }
}
