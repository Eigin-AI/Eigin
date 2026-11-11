use super::*;
use crate::{
    DiagnosticEvent, DiagnosticOptions, DiagnosticReceiver, clear_diagnostic_receiver,
    set_diagnostic_receiver,
};
use std::sync::{Arc, Mutex};

struct Receiver(Arc<Mutex<Vec<DiagnosticEvent>>>);

impl DiagnosticReceiver for Receiver {
    fn receive(&self, event: DiagnosticEvent) {
        self.0.lock().unwrap().push(event);
    }
}

#[test]
fn stream_events_share_an_operation_id() {
    let _registration = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let events = Arc::new(Mutex::new(Vec::new()));
    set_diagnostic_receiver(
        Box::new(Receiver(events.clone())),
        DiagnosticOptions::default(),
    );
    let (provider, _) = provider("https://example.test/v1", 200, finished());
    let stream = provider.stream(input()).unwrap();
    block_on(async { while stream.next().await.unwrap().is_some() {} });
    stream.cancel();
    clear_diagnostic_receiver();

    let events = events.lock().unwrap();
    assert!(!events.is_empty());
    let context = events[0].context.as_ref().unwrap();
    assert!(
        events
            .iter()
            .all(|event| event.context.as_ref() == Some(context))
    );
    assert!(!events.iter().any(|event| event.message == "cancelled"));
}

fn field<'a>(event: &'a DiagnosticEvent, name: &str) -> &'a str {
    event
        .fields
        .iter()
        .find(|field| field.name == name)
        .unwrap()
        .value
        .as_deref()
        .unwrap()
}

#[test]
fn stream_excerpts_follow_opt_in_and_are_bounded() {
    let _registration = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    for include_private in [false, true] {
        let events = Arc::new(Mutex::new(Vec::new()));
        set_diagnostic_receiver(
            Box::new(Receiver(events.clone())),
            DiagnosticOptions {
                include_private,
                ..Default::default()
            },
        );
        let (provider, _) = provider(
            "https://example.test/v1",
            200,
            sse(&[chunk(json!({"content": "p".repeat(400)}), Some("stop"))]),
        );
        let stream = provider.stream(input()).unwrap();
        block_on(async { while stream.next().await.unwrap().is_some() {} });
        clear_diagnostic_receiver();

        let events = events.lock().unwrap();
        let first = events
            .iter()
            .find(|event| event.message == "first event")
            .unwrap();
        let excerpt = first
            .fields
            .iter()
            .find(|field| field.name == "excerpt")
            .unwrap();
        assert_eq!(excerpt.privacy, crate::DiagnosticPrivacy::Private);
        assert_eq!(excerpt.value, include_private.then(|| "p".repeat(256)));
        assert!(!format!("{events:?}").contains("test-key"));
        let finished = events
            .iter()
            .find(|event| event.message == "request finished")
            .unwrap();
        assert_eq!(field(finished, "events_delivered"), "2");
        assert_eq!(field(finished, "status"), "200");
        assert!(field(finished, "bytes_received").parse::<u64>().unwrap() > 0);
        assert!(field(finished, "elapsed_ms").parse::<u128>().is_ok());
    }
}

#[test]
fn discovery_and_validation_have_separate_correlated_lifecycles() {
    let _registration = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let events = Arc::new(Mutex::new(Vec::new()));
    set_diagnostic_receiver(
        Box::new(Receiver(events.clone())),
        DiagnosticOptions::default(),
    );
    let (models, _) = provider("https://example.test/v1", 200, r#"{"data":[]}"#);
    let (validation, _) = provider("https://example.test/v1", 401, "");
    block_on(models.discovery().fetch_models()).unwrap();
    assert!(
        block_on(
            validation
                .key_validation()
                .validate_api_key("private-model".into())
        )
        .is_err()
    );
    clear_diagnostic_receiver();

    let events = events.lock().unwrap();
    assert_eq!(events.len(), 6);
    assert_ne!(events[0].context, events[3].context);
    for (group, kind, status, terminal) in [
        (&events[..3], "discovery", "200", "request finished"),
        (&events[3..], "key validation", "401", "request failed"),
    ] {
        assert!(group.iter().all(|event| event.context == group[0].context));
        assert_eq!(group[0].message, "request started");
        assert_eq!(group[1].message, "response headers");
        assert_eq!(group[2].message, terminal);
        assert_eq!(field(&group[2], "operation"), kind);
        assert_eq!(field(&group[2], "status"), status);
        assert!(field(&group[2], "elapsed_ms").parse::<u128>().is_ok());
    }
    assert!(!format!("{events:?}").contains("private-model"));
}

#[test]
fn text_only_eof_without_a_trailing_newline_reports_success_once() {
    let _registration = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let events = Arc::new(Mutex::new(Vec::new()));
    set_diagnostic_receiver(
        Box::new(Receiver(events.clone())),
        DiagnosticOptions::default(),
    );
    let body = sse(&[chunk(json!({"content": "last text"}), None)]);
    let (provider, _) = provider("https://example.test/v1", 200, body.trim_end());
    let stream = provider
        .stream(InferenceCompletionInput {
            text_only: true,
            ..input()
        })
        .unwrap();
    block_on(async {
        assert!(
            matches!(stream.next().await.unwrap(), Some(InferenceEvent::ContentDelta { text }) if text == "last text")
        );
        assert!(stream.next().await.unwrap().is_none());
        assert!(stream.next().await.unwrap().is_none());
    });
    stream.cancel();
    drop(stream);
    clear_diagnostic_receiver();

    let events = events.lock().unwrap();
    assert_eq!(
        events
            .iter()
            .filter(|event| event.message == "request finished")
            .count(),
        1
    );
    assert!(
        !events
            .iter()
            .any(|event| event.message == "cancelled" || event.message == "request failed")
    );
}
