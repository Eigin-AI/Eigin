use super::ConversationMessage;
use icu_normalizer::ComposingNormalizer;
use std::{borrow::Cow, collections::HashMap};

/// Swift compares canonically equivalent strings; normalize comparison keys only.
pub(crate) fn key(value: &str) -> Cow<'_, str> {
    ComposingNormalizer::new_nfc().normalize(value)
}

pub(super) fn same_payload(a: &ConversationMessage, b: &ConversationMessage) -> bool {
    let (Some(a_id), Some(b_id)) = (&a.tool_call_id, &b.tool_call_id) else {
        return false;
    };
    key(a_id) == key(b_id)
        && metadata_entries(&a.provider_metadata) == metadata_entries(&b.provider_metadata)
        && canonical_payload(a) == canonical_payload(b)
}

fn canonical_payload(message: &ConversationMessage) -> ConversationMessage {
    let mut value = message.clone();
    value.source_index = None;
    value.role.clear();
    for text in [&mut value.content, &mut value.name, &mut value.tool_call_id]
        .into_iter()
        .flatten()
    {
        *text = key(text).into_owned();
    }
    for call in value.tool_calls.iter_mut().flatten() {
        for text in [
            &mut call.id,
            &mut call.kind,
            &mut call.name,
            &mut call.arguments,
        ] {
            *text = key(text).into_owned();
        }
    }
    for attachment in value.attachments.iter_mut().flatten() {
        for text in [
            &mut attachment.id,
            &mut attachment.kind,
            &mut attachment.mime_type,
        ] {
            *text = key(text).into_owned();
        }
    }
    value.provider_metadata = None;
    if let Some(reasoning) = &mut value.reasoning_history {
        for text in [
            &mut reasoning.origin.provider_id,
            &mut reasoning.origin.endpoint,
            &mut reasoning.origin.model,
            &mut reasoning.format,
            &mut reasoning.visible_text,
        ] {
            *text = key(text).into_owned();
        }
    }
    value
}

// Keep canonical-key collisions as separate entries when comparing SDK callers' maps.
fn metadata_entries(metadata: &Option<HashMap<String, String>>) -> Option<Vec<(String, String)>> {
    metadata.as_ref().map(|metadata| {
        let mut entries: Vec<_> = metadata
            .iter()
            .map(|(k, v)| (key(k).into_owned(), key(v).into_owned()))
            .collect();
        entries.sort_unstable();
        entries
    })
}
