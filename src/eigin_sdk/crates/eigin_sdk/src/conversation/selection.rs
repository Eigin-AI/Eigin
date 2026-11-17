use super::{ConversationMessage, ConversationPreparationError, SelectedConversation};

/// Selects the latest summary and retained history; assigns original snapshot indices.
#[uniffi::export]
pub fn conversation_select(
    mut history: Vec<ConversationMessage>,
) -> Result<SelectedConversation, ConversationPreparationError> {
    for (index, message) in history.iter_mut().enumerate() {
        message.source_index = Some(index as u64);
    }
    let Some(index) = history.iter().rposition(|m| m.is_compaction_summary) else {
        return Ok(SelectedConversation {
            summary: None,
            messages: history,
        });
    };
    let summary = history[index].content.clone();
    let retained = history[index]
        .compaction_retained_message_count
        .unwrap_or(0);
    if retained < 0 {
        return Err(ConversationPreparationError::InvalidRetainedCount {
            source_index: index as u64,
        });
    }
    let retained = retained as u64;
    let start = index.saturating_sub(usize::try_from(retained).unwrap_or(usize::MAX));
    let messages = history
        .into_iter()
        .enumerate()
        .filter(|(i, m)| *i >= start && !m.is_compaction_summary)
        .map(|(_, m)| m)
        .collect();
    Ok(SelectedConversation { summary, messages })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn text(role: &str, content: &str) -> ConversationMessage {
        ConversationMessage::text(role, content.into())
    }

    fn summary(content: &str, retained: i64) -> ConversationMessage {
        ConversationMessage {
            is_compaction_summary: true,
            compaction_retained_message_count: Some(retained),
            ..text("system", content)
        }
    }

    #[test]
    fn selects_latest_summary_retained_history_and_original_indices() {
        let history = vec![
            text("user", "old"),
            summary("old summary", 1),
            text("user", "retained"),
            summary("latest", 2),
            text("assistant", "new"),
        ];
        let original = history.clone();
        let selected = conversation_select(history.clone()).unwrap();
        assert_eq!(selected.summary.as_deref(), Some("latest"));
        assert_eq!(
            selected
                .messages
                .iter()
                .map(|m| m.source_index)
                .collect::<Vec<_>>(),
            vec![Some(2), Some(4)]
        );
        assert_eq!(history, original);
        let all = conversation_select(vec![text("user", "retained"), summary("latest", i64::MAX)])
            .unwrap();
        assert_eq!(all.messages.len(), 1);
        assert_eq!(conversation_select(vec![]).unwrap().messages.len(), 0);
        assert_eq!(
            conversation_select(vec![text("user", "only")])
                .unwrap()
                .messages[0]
                .source_index,
            Some(0)
        );
    }

    #[test]
    fn rejects_negative_retained_counts_without_panicking() {
        for count in [-1, i64::MIN] {
            assert_eq!(
                conversation_select(vec![text("user", "old"), summary("memory", count)]),
                Err(ConversationPreparationError::InvalidRetainedCount { source_index: 1 })
            );
        }
    }
}
