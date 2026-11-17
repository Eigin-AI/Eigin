use super::fixtures::*;
use crate::conversation::*;
use crate::inference::{InferenceReasoningHistory, InferenceReasoningOrigin};
use std::collections::HashMap;

#[test]
fn repairs_rounds_before_inserting_synthetic_system_message() {
    let valid = vec![call(&["a", "b"]), tool("b", "two"), tool("a", "one")];
    assert_eq!(prepare(valid.clone(), true, None).len(), 4);
    for history in [
        vec![call(&["a", "b"]), tool("a", "one")],
        vec![tool("a", "orphan")],
        vec![call(&["a"]), tool("a", "one"), tool("extra", "extra")],
    ] {
        assert_eq!(prepare(history, true, None).len(), 1);
    }
    let after_system = [vec![text("system", "existing")], valid.clone()].concat();
    assert_eq!(prepare(after_system, true, None).len(), 2);
    let after_summary = [vec![summary("memory", 0)], valid].concat();
    assert_eq!(prepare(after_summary, true, None).len(), 6);
}

#[test]
fn repairs_duplicate_results_and_interruption_only_when_unambiguous() {
    let result = tool("a", "real");
    let placeholder = tool("a", INTERRUPTED);
    let history = vec![
        call(&["a"]),
        placeholder.clone(),
        result.clone(),
        result.clone(),
    ];
    let output = prepare(history, true, None);
    assert_eq!(output.len(), 3);
    assert_eq!(
        output[2].origin,
        PreparedConversationOrigin::History { source_index: 2 }
    );
    assert_eq!(output[2].message.content.as_deref(), Some("real"));
    assert_eq!(
        prepare(vec![call(&["a"]), placeholder.clone()], true, None).len(),
        3
    );
    assert_eq!(
        prepare(
            vec![
                call(&["a"]),
                placeholder,
                result.clone(),
                tool("a", "conflict")
            ],
            true,
            None
        )
        .len(),
        5
    );
    assert_eq!(
        prepare(vec![call(&["a", "a"]), result.clone(), result], true, None).len(),
        4
    );
}

#[test]
fn duplicate_equivalence_preserves_optional_metadata_and_reasoning() {
    let original = tool("a", "same");
    let mut variations = vec![];
    let mut changed = original.clone();
    changed.provider_metadata = Some(HashMap::new());
    variations.push(changed);
    let mut changed = original.clone();
    changed.tool_calls = Some(vec![]);
    variations.push(changed);
    let mut changed = original.clone();
    changed.attachments = Some(vec![]);
    variations.push(changed);
    let mut changed = original.clone();
    changed.name = Some("lookup".into());
    variations.push(changed);
    let mut changed = original.clone();
    changed.compaction_retained_message_count = Some(0);
    variations.push(changed);
    let mut changed = original.clone();
    changed.reasoning_history = Some(InferenceReasoningHistory {
        origin: InferenceReasoningOrigin {
            provider_id: "provider".into(),
            endpoint: "endpoint".into(),
            model: "model".into(),
        },
        format: "opaque".into(),
        payload: vec![0, 255],
        visible_text: "same".into(),
        additional_input_tokens: 42,
    });
    variations.push(changed);
    for different in variations {
        let output = prepare(
            vec![call(&["a"]), original.clone(), different.clone()],
            true,
            None,
        );
        assert_eq!(output.len(), 4, "must preserve {different:?}");
    }
}

#[test]
fn append_hint_does_not_repair_or_select_an_assembled_request() {
    let mut output = prepare(
        vec![text("user", "question"), call(&["a"]), tool("a", "result")],
        true,
        None,
    );
    output.push(PreparedConversationMessage {
        origin: PreparedConversationOrigin::Supplied,
        message: tool("x", "request-local"),
    });
    let copy = output.clone();
    let hinted = conversation_append_hint(output, "hint".into());
    assert_eq!(hinted.len(), copy.len());
    assert_eq!(
        hinted[1].message.content.as_deref(),
        Some("question\n\nhint")
    );
    assert_eq!(hinted[2..], copy[2..]);
}

#[test]
fn canonical_unicode_equivalence_matches_swift_without_rewriting_payloads() {
    let mut first = tool("é", "café");
    first.provider_metadata = Some(HashMap::from([("clé".into(), "café".into())]));
    let mut second = tool("e\u{301}", "cafe\u{301}");
    second.provider_metadata = Some(HashMap::from([("cle\u{301}".into(), "cafe\u{301}".into())]));
    let output = prepare(vec![call(&["e\u{301}"]), first.clone(), second], true, None);
    assert_eq!(output.len(), 3);
    assert_eq!(output[2].message.content, first.content);
    assert_eq!(output[2].message.tool_call_id, first.tool_call_id);
    assert_eq!(output[2].message.provider_metadata, first.provider_metadata);
}

#[test]
fn repair_preserves_order_content_and_round_boundaries() {
    let history = vec![
        text("user", "start"),
        call(&["a"]),
        tool("a", "result"),
        call(&["missing"]),
        text("user", "continue"),
        call(&["a"]),
        tool("a", "result"),
    ];
    let output = prepare(history, true, None);
    assert_eq!(
        contents(&output),
        vec![
            "instructions",
            "start",
            "",
            "result",
            "continue",
            "",
            "result"
        ]
    );
    let output = prepare(
        vec![
            call(&["a"]),
            tool("a", "result"),
            tool("extra", "stray"),
            call(&["b"]),
            tool("b", "good"),
        ],
        true,
        None,
    );
    assert_eq!(contents(&output), vec!["instructions", "", "good"]);
    let mut thinking = call(&["a"]);
    thinking.content = Some("thinking".into());
    assert_eq!(
        prepare(vec![thinking.clone(), tool("a", "result")], true, None)[1]
            .message
            .content,
        thinking.content
    );
    assert_eq!(prepare(vec![thinking], true, None).len(), 1);
}

#[test]
fn ambiguous_interruption_payloads_are_not_removed() {
    let base = tool("a", INTERRUPTED);
    let mut variants = vec![];
    let mut m = base.clone();
    m.provider_metadata = Some(HashMap::from([("signature".into(), "private".into())]));
    variants.push(m);
    let mut m = base.clone();
    m.attachments = image("tool", "image").attachments;
    variants.push(m);
    let mut m = base.clone();
    m.name = Some("different".into());
    variants.push(m);
    let mut m = base.clone();
    m.content.as_mut().unwrap().push_str(" Additional output.");
    variants.push(m);
    for variant in variants {
        assert_eq!(
            prepare(vec![call(&["a"]), variant, tool("a", "real")], true, None).len(),
            4
        );
    }
    for results in [
        vec![base.clone(), tool("a", "real")],
        vec![tool("a", "real"), base.clone()],
    ] {
        let output = prepare([vec![call(&["a"])], results].concat(), true, None);
        assert_eq!(contents(&output), vec!["instructions", "", "real"]);
    }
    assert_eq!(
        prepare(
            vec![call(&["a"]), base.clone(), base.clone(), base],
            true,
            None
        )
        .len(),
        3
    );
}

#[test]
fn optional_tool_ids_and_empty_calls_keep_existing_repair_semantics() {
    let mut empty_calls = text("assistant", "answer");
    empty_calls.tool_calls = Some(vec![]);
    assert_eq!(
        prepare(vec![empty_calls, tool("a", "orphan")], true, None).len(),
        2
    );
    // Results without IDs do not enter the set comparison and remain when the round is complete.
    let output = prepare(
        vec![call(&["a"]), tool("a", "real"), text("tool", "no ID")],
        true,
        None,
    );
    assert_eq!(output.len(), 4);
}

#[test]
fn canonical_nested_payloads_collapse_but_distinct_reasoning_bytes_do_not() {
    let mut first = tool("a", "é");
    first.name = Some("é".into());
    first.attachments = image("tool", "image").attachments;
    first.attachments.as_mut().unwrap()[0].mime_type = "é".into();
    first.tool_calls = call(&["é"]).tool_calls;
    first.reasoning_history = Some(InferenceReasoningHistory {
        origin: InferenceReasoningOrigin {
            provider_id: "é".into(),
            endpoint: "é".into(),
            model: "é".into(),
        },
        format: "é".into(),
        payload: vec![255],
        visible_text: "é".into(),
        additional_input_tokens: 1,
    });
    let mut second = first.clone();
    second.content = Some("e\u{301}".into());
    second.name = second.content.clone();
    second.attachments.as_mut().unwrap()[0].mime_type = "e\u{301}".into();
    second.tool_calls.as_mut().unwrap()[0].id = "e\u{301}".into();
    let reasoning = second.reasoning_history.as_mut().unwrap();
    reasoning.origin.provider_id = "e\u{301}".into();
    reasoning.origin.endpoint = "e\u{301}".into();
    reasoning.origin.model = "e\u{301}".into();
    reasoning.format = "e\u{301}".into();
    reasoning.visible_text = "e\u{301}".into();
    assert_eq!(
        prepare(
            vec![call(&["a"]), first.clone(), second.clone()],
            true,
            None
        )
        .len(),
        3
    );
    second.reasoning_history.as_mut().unwrap().payload = vec![254];
    assert_eq!(
        prepare(vec![call(&["a"]), first, second], true, None).len(),
        4
    );
}

#[test]
fn metadata_key_collisions_preserve_conflicting_results() {
    for values in [("same", "same"), ("first", "second")] {
        let mut collision = tool("a", "result");
        collision.provider_metadata = Some(HashMap::from([
            ("é".into(), values.0.into()),
            ("e\u{301}".into(), values.1.into()),
        ]));
        for value in [values.0, values.1] {
            let mut single = tool("a", "result");
            single.provider_metadata = Some(HashMap::from([("é".into(), value.into())]));
            let output = prepare(
                vec![call(&["a"]), collision.clone(), single.clone()],
                true,
                None,
            );
            assert_eq!(output.len(), 4);
            assert_eq!(
                output[2].message.provider_metadata,
                collision.provider_metadata
            );
            assert_eq!(
                output[3].message.provider_metadata,
                single.provider_metadata
            );
        }
        let output = prepare(
            vec![call(&["a"]), collision.clone(), collision.clone()],
            true,
            None,
        );
        assert_eq!(output.len(), 3);
        assert_eq!(
            output[2].message.provider_metadata,
            collision.provider_metadata
        );
    }
}
