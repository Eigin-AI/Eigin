use super::{
    PreparedConversationMessage, PreparedConversationOrigin,
    types::{append_text, synthetic},
};

/// Appends supplied text to the last user message, or creates a user message when absent.
///
/// Supply nonempty hints. Empty text adds a separator to nonempty content or an empty fallback message.
#[uniffi::export]
pub fn conversation_append_hint(
    mut messages: Vec<PreparedConversationMessage>,
    hint: String,
) -> Vec<PreparedConversationMessage> {
    if let Some(entry) = messages.iter_mut().rev().find(|m| m.message.role == "user") {
        append_text(&mut entry.message, &hint);
    } else {
        messages.push(synthetic(
            PreparedConversationOrigin::HintFallback,
            "user",
            hint,
        ));
    }
    messages
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn standalone_empty_hint_appends_separator_or_fallback() {
        let output = vec![synthetic(
            PreparedConversationOrigin::Supplied,
            "user",
            "question".into(),
        )];
        let hinted = conversation_append_hint(output, String::new());
        assert_eq!(hinted[0].message.content.as_deref(), Some("question\n\n"));
        let fallback = conversation_append_hint(vec![], String::new());
        assert_eq!(fallback[0].origin, PreparedConversationOrigin::HintFallback);
        assert_eq!(fallback[0].message.content.as_deref(), Some(""));
    }
}
