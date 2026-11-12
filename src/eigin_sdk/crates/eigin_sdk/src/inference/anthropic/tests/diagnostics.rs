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
fn response_excerpts_require_private_diagnostics_and_never_include_credentials() {
    let _lock = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
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
            "https://example.test",
            200,
            sse(&[
                json!({"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"private-response".repeat(40)}}),
            ]) + &finish("end_turn"),
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
        assert_eq!(
            excerpt.value,
            include_private.then(|| "private-response".repeat(40).chars().take(256).collect())
        );
        assert!(!format!("{events:?}").contains("test-key"));

        if !include_private {
            assert!(!format!("{events:?}").contains("private-response"));
        }
    }
}
