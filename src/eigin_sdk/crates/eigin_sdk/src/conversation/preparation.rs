use super::{
    ConversationPreparationOptions, PreparedConversationMessage, PreparedConversationOrigin,
    SelectedConversation, attachments::strip_attachments, hints::conversation_append_hint, repair,
    types::synthetic,
};

const ACKNOWLEDGEMENT: &str = "Understood — continuing from there.";

/// Assembles request-only messages, preserving the supplied history and metadata.
#[uniffi::export]
pub fn conversation_prepare(
    selected: SelectedConversation,
    options: ConversationPreparationOptions,
) -> Vec<PreparedConversationMessage> {
    let mut messages = vec![synthetic(
        PreparedConversationOrigin::System,
        "system",
        options.system_prompt,
    )];
    if let Some(summary) = selected.summary.filter(|s| !s.is_empty()) {
        messages.push(synthetic(
            PreparedConversationOrigin::Summary,
            "user",
            format!("<conversation_summary>\n{summary}\n</conversation_summary>"),
        ));
        messages.push(synthetic(
            PreparedConversationOrigin::SummaryAcknowledgement,
            "assistant",
            ACKNOWLEDGEMENT.into(),
        ));
    }
    messages.extend(
        repair::repair(strip_attachments(
            selected.messages,
            options.supports_vision,
        ))
        .into_iter()
        .map(|message| {
            let origin = message
                .source_index
                .map_or(PreparedConversationOrigin::Supplied, |source_index| {
                    PreparedConversationOrigin::History { source_index }
                });
            PreparedConversationMessage { origin, message }
        }),
    );
    if let Some(hint) = options.system_hint.filter(|h| !h.is_empty()) {
        messages = conversation_append_hint(messages, hint);
    }
    messages
}
