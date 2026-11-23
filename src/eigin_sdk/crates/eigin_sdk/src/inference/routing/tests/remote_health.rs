use super::{super::*, fixtures::*};

#[test]
fn remote_evidence_hysteresis_local_precedence_and_provider_scope() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let router = ModelRouter::new();
    router.replace_remote_health("provider".into(), vec![remote(vec![sample(11000.0, 0.0)])]);
    assert_eq!(router.resolve(request(), 1.0, 1.0).model, "b");
    router.replace_remote_health("provider".into(), vec![remote(vec![sample(9000.0, 2.0)])]);
    assert_eq!(router.resolve(request(), 3.0, 3.0).model, "b");
    let mut other = request();
    other.inventory.as_mut().unwrap().provider_id = "another".into();
    other.provider_id = "another".into();
    assert_eq!(router.resolve(other, 3.0, 3.0).model, "a");
    router.record(outcome("a", RoutingResult::Succeeded), 4.0);
    assert_eq!(router.resolve(request(), 4.0, 4.0).model, "b"); // No local TTFT measurement.
    let mut success = outcome("a", RoutingResult::Succeeded);
    success.first_token_seconds = Some(1.0);
    router.record(success, 5.0);
    assert_eq!(router.resolve(request(), 5.0, 5.0).model, "a");
}

#[test]
fn remote_expiry_future_and_insufficient_samples() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let router = ModelRouter::new();
    let mut sparse = sample(11000.0, 0.0);
    sparse.count = 2;
    router.replace_remote_health(
        "provider".into(),
        vec![remote(vec![sparse, sample(11000.0, 2.0)])],
    );
    assert_eq!(router.resolve(request(), 1.0, 1.0).model, "a");
    assert_eq!(router.resolve(request(), 2.0, 2.0).model, "b");
    assert_eq!(router.resolve(request(), 100.0, 100.0).model, "a");
}

#[test]
fn remote_failure_threshold_and_reason_precedence() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let router = ModelRouter::new();
    let mut health = remote(vec![sample(11000.0, 0.0)]);
    health.tps = vec![sample(4.0, 0.0)];
    let mut failure = sample(0.5, 0.0);
    failure.count = 3;
    health.failures = vec![failure.clone()];
    router.replace_remote_health("provider".into(), vec![health.clone()]);
    assert_eq!(
        router.resolve(request(), 0.0, 0.0).change,
        Some(RoutingChange::ModelDegraded {
            previous: "a".into(),
            reason: RoutingDegradation::SlowFirstToken
        })
    );
    failure.count = 4;
    health.failures = vec![failure];
    router.replace_remote_health("provider".into(), vec![health]);
    assert_eq!(
        router.resolve(request(), 0.0, 0.0).change,
        Some(RoutingChange::ModelDegraded {
            previous: "a".into(),
            reason: RoutingDegradation::Errors
        })
    );
    router.record(outcome("a", RoutingResult::Succeeded), 0.0);
    assert_eq!(
        router.resolve(request(), 0.0, 0.0).change,
        Some(RoutingChange::ModelDegraded {
            previous: "a".into(),
            reason: RoutingDegradation::Errors
        })
    );
    router.record(outcome("a", RoutingResult::Succeeded), 1.0);
    assert_eq!(
        router.resolve(request(), 1.0, 1.0).change,
        Some(RoutingChange::ModelDegraded {
            previous: "a".into(),
            reason: RoutingDegradation::SlowFirstToken
        })
    );
}

#[test]
fn remote_speed_recovery_is_strict_and_probe_needs_one_sample() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let router = ModelRouter::new();
    let mut health = remote(vec![]);
    let mut probe = sample(4.0, 0.0);
    probe.probe = true;
    probe.count = 1;
    health.tps = vec![probe];
    router.replace_remote_health("provider".into(), vec![health.clone()]);
    assert_eq!(router.resolve(request(), 0.0, 0.0).model, "b");
    health.tps = vec![sample(6.0, 1.0)];
    router.replace_remote_health("provider".into(), vec![health.clone()]);
    assert_eq!(router.resolve(request(), 1.0, 1.0).model, "b");
    health.tps = vec![sample(6.1, 2.0)];
    router.replace_remote_health("provider".into(), vec![health]);
    assert_eq!(router.resolve(request(), 2.0, 2.0).model, "a");
    for (time, value, expected) in [(3.0, 10000.1, "b"), (4.0, 8000.0, "b"), (5.0, 7999.9, "a")] {
        router.replace_remote_health("provider".into(), vec![remote(vec![sample(value, time)])]);
        assert_eq!(router.resolve(request(), time, time).model, expected);
    }
}

#[test]
fn selection_and_change_reason_use_their_original_clock_positions() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let router = ModelRouter::new();
    let mut r = request();
    r.message_needs_reasoning = true;
    r.inventory.as_mut().unwrap().models[1].supports_reasoning = true;
    let mut health = remote(vec![sample(11000.0, 0.0)]);
    health.ttft[0].expires_at = 1.0;
    router.replace_remote_health("provider".into(), vec![health]);
    assert_eq!(
        router.resolve(r, 0.0, 1.0),
        decision(
            "b",
            Some(RoutingChange::SteppedUp {
                previous: "a".into()
            })
        )
    );
    // Candidate selection still sees evidence at request start; reason sees expiry.
    let mut health = remote(vec![sample(11000.0, 0.0)]);
    health.ttft[0].expires_at = 1.0;
    router.replace_remote_health("provider".into(), vec![health]);
    assert_eq!(
        router
            .replacement(
                request(),
                RoutingFailure::PreAnswerBufferLimit,
                None,
                0.0,
                1.0
            )
            .unwrap()
            .change,
        Some(RoutingChange::ModelDegraded {
            previous: "a".into(),
            reason: RoutingDegradation::Errors
        })
    );
}
