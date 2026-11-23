use super::{super::*, fixtures::*};

#[test]
fn retirement_is_model_scoped_and_handles_are_isolated() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let router = ModelRouter::new();
    router.record(outcome("a", failed(RoutingFailure::ModelNotFound)), 0.0);
    let mut r = request();
    r.provider_id = "another".into();
    r.inventory.as_mut().unwrap().provider_id = "another".into();
    assert_eq!(
        router.resolve(r.clone(), 0.0, 0.0),
        decision(
            "b",
            Some(RoutingChange::ModelRetired {
                previous: "a".into()
            })
        )
    );
    assert_eq!(ModelRouter::new().resolve(r, 0.0, 0.0).model, "a");
    assert!(
        router
            .replacement(
                request(),
                RoutingFailure::ModelNotFound,
                Option::None,
                0.0,
                0.0
            )
            .is_some()
    );
    let mut r = request();
    r.current_model = "b".into();
    assert!(
        router
            .replacement(r, RoutingFailure::ModelNotFound, Option::None, 0.0, 0.0)
            .is_none()
    );
}

#[test]
fn success_resets_backoff_without_removing_current_quarantine() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let router = ModelRouter::new();
    router.record(outcome("a", failed(RoutingFailure::TimedOut)), 0.0);
    router.record(outcome("a", failed(RoutingFailure::TimedOut)), 1.0);
    router.record(outcome("a", RoutingResult::Succeeded), 2.0);
    assert_eq!(router.resolve(request(), 600.0, 600.0).model, "b");
    assert_eq!(router.resolve(request(), 601.0, 601.0).model, "a");
    router.record(outcome("a", failed(RoutingFailure::TimedOut)), 602.0);
    assert_eq!(router.resolve(request(), 901.0, 901.0).model, "b");
    assert_eq!(router.resolve(request(), 902.0, 902.0).model, "a");
}

#[test]
fn quarantine_caps_at_one_hour_and_cancellation_does_not_reset_it() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let router = ModelRouter::new();
    for now in 0..10 {
        router.record(outcome("a", failed(RoutingFailure::TimedOut)), now as f64);
    }
    router.record(outcome("a", RoutingResult::Cancelled), 10.0);
    assert_eq!(router.resolve(request(), 3608.0, 3608.0).model, "b");
    assert_eq!(router.resolve(request(), 3609.0, 3609.0).model, "a");
}

#[test]
fn sample_window_evicts_slow_observations_and_includes_throughput() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let router = ModelRouter::new();
    for (index, speed) in [4.0, 4.0, 5.0, 5.0, 4.0, 4.0].into_iter().enumerate() {
        let mut success = outcome("a", RoutingResult::Succeeded);
        success.tokens_per_second = Some(speed);
        router.record(success, index as f64);
        assert_eq!(
            router.resolve(request(), index as f64, index as f64).model,
            "a"
        );
    }
    let mut success = outcome("a", RoutingResult::Succeeded);
    success.tokens_per_second = Some(4.0);
    router.record(success, 6.0);
    assert_eq!(router.resolve(request(), 6.0, 6.0).model, "b");
}

#[test]
fn slow_success_and_hedge_loss_sequences() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let router = ModelRouter::new();
    let mut slow = outcome("a", RoutingResult::Succeeded);
    slow.first_token_seconds = Some(11.0);
    router.record(slow.clone(), 0.0);
    assert_eq!(router.hedge_delay("a".into()), 6.0);
    router.record(slow.clone(), 1.0);
    assert_eq!(router.hedge_delay("a".into()), 3.0);
    router.record(slow, 2.0);
    assert_eq!(router.resolve(request(), 2.0, 2.0).model, "b");
    assert_eq!(router.resolve(request(), 122.0, 122.0).model, "a");
    router.record_hedge_loss("a".into(), 123.0);
    assert_eq!(router.resolve(request(), 123.0, 123.0).model, "a");
    router.record_hedge_loss("a".into(), 124.0);
    assert_eq!(router.resolve(request(), 124.0, 124.0).model, "b");
}
