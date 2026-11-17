use super::fixtures::*;
use crate::conversation::*;

#[test]
fn assembles_summary_hint_and_preserves_inputs() {
    let selected =
        conversation_select(vec![summary("memory", 0), image("user", "question")]).unwrap();
    let snapshot = selected.clone();
    let output = conversation_prepare(
        selected.clone(),
        options(true, Some("<system_hint>hint</system_hint>")),
    );
    assert_eq!(
        contents(&output),
        vec![
            "instructions",
            "<conversation_summary>\nmemory\n</conversation_summary>",
            ACKNOWLEDGEMENT,
            "question\n\n<system_hint>hint</system_hint>"
        ]
    );
    assert_eq!(
        output[3].origin,
        PreparedConversationOrigin::History { source_index: 1 }
    );
    assert!(output[3].message.attachments.is_some());
    assert_eq!(selected, snapshot);
    assert_eq!(
        output,
        conversation_prepare(
            selected,
            options(true, Some("<system_hint>hint</system_hint>"))
        )
    );
}

#[test]
fn hint_falls_back_to_summary_or_new_user_and_empty_hint_is_ignored() {
    let output = prepare(vec![summary("memory", 0)], true, Some("hint"));
    assert_eq!(
        output[1].message.content.as_deref(),
        Some("<conversation_summary>\nmemory\n</conversation_summary>\n\nhint")
    );
    let output = prepare(vec![], true, Some("hint"));
    assert_eq!(output[1].origin, PreparedConversationOrigin::HintFallback);
    assert_eq!(output[1].message.role, "user");
    assert_eq!(
        contents(&prepare(vec![text("user", "")], true, Some("hint"))),
        vec!["instructions", "hint"]
    );
    assert_eq!(prepare(vec![summary("", 0)], true, Some("")).len(), 1);
    assert_eq!(prepare(vec![], true, None).len(), 1);
}

#[test]
fn retains_two_attachment_messages_including_non_user_roles() {
    let history = vec![
        image("user", "first"),
        image("assistant", "second"),
        image("user", "third"),
    ];
    let output = prepare(history.clone(), true, None);
    assert_eq!(
        output[1].message.content.as_deref(),
        Some("first\n\n[image omitted]")
    );
    assert!(output[1].message.attachments.is_none());
    assert!(output[2].message.attachments.is_some());
    assert!(output[3].message.attachments.is_some());
    assert!(history[0].attachments.is_some());
    let blind = prepare(history, false, None);
    assert!(blind[1..].iter().all(|m| m.message.attachments.is_none()));
    assert_eq!(
        blind[1].message.content.as_deref(),
        Some(format!("first\n\n{VISION_UNSUPPORTED}").as_str())
    );
    let empty = prepare(vec![image("user", "")], false, None);
    assert_eq!(
        empty[1].message.content.as_deref(),
        Some(VISION_UNSUPPORTED)
    );
    let mut no_images = text("user", "text");
    no_images.attachments = Some(vec![]);
    assert_eq!(
        prepare(vec![no_images.clone()], false, None)[1]
            .message
            .attachments,
        no_images.attachments
    );
}
