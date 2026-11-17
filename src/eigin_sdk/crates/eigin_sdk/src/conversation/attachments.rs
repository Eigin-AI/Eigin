use super::{ConversationMessage, types::append_text};

const IMAGE_OMITTED: &str = "[image omitted]";
const VISION_UNSUPPORTED: &str = "[an image was attached here, but this model cannot view images]";

pub(super) fn strip_attachments(
    mut messages: Vec<ConversationMessage>,
    supports_vision: bool,
) -> Vec<ConversationMessage> {
    let mut remaining = if supports_vision { 2 } else { 0 };
    for message in messages.iter_mut().rev() {
        if message.attachments.as_ref().is_none_or(Vec::is_empty) {
            continue;
        }
        if remaining > 0 {
            remaining -= 1;
        } else {
            message.attachments = None;
            append_text(
                message,
                if supports_vision {
                    IMAGE_OMITTED
                } else {
                    VISION_UNSUPPORTED
                },
            );
        }
    }
    messages
}
