use super::{super::*, fixtures::*};

#[test]
fn quarantine_expiry_backoff_and_idle_reset_boundaries() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let router = ModelRouter::new();
    router.record(
        outcome("a", failed(RoutingFailure::ProviderOverloaded)),
        0.0,
    );
    assert_eq!(router.resolve(request(), 299.0, 299.0).model, "b");
    assert_eq!(router.resolve(request(), 300.0, 300.0).model, "a");
    router.record(
        outcome("a", failed(RoutingFailure::ProviderOverloaded)),
        300.0,
    );
    assert_eq!(router.resolve(request(), 899.0, 899.0).model, "b");
    assert_eq!(router.resolve(request(), 900.0, 900.0).model, "a");
    router.record(outcome("a", failed(RoutingFailure::ModelNotFound)), 900.0);
    assert_eq!(router.resolve(request(), 4500.0, 4500.0).model, "b");
    assert_eq!(router.resolve(request(), 4500.1, 4500.1).model, "a");
}

#[test]
fn conversation_anchor_survives_global_model_change_until_idle_reset() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let router = ModelRouter::new();
    let mut r = request();
    r.conversation_id = Some("conversation".into());
    assert_eq!(router.resolve(r.clone(), 0.0, 0.0).model, "a");
    assert_eq!(
        router
            .replacement(
                r.clone(),
                RoutingFailure::ProviderOverloaded,
                Option::None,
                0.0,
                0.0
            )
            .unwrap()
            .model,
        "b"
    );
    assert_eq!(router.resolve(r.clone(), 301.0, 301.0).model, "b");
    let mut fresh = r.clone();
    fresh.conversation_id = Some("fresh".into());
    assert_eq!(router.resolve(fresh, 301.0, 301.0).model, "a");
    router.mark_activity(3500.0);
    assert_eq!(router.resolve(r.clone(), 4000.0, 4000.0).model, "b");
    assert_eq!(router.resolve(r, 7100.1, 7100.1), decision("a", None));
}
