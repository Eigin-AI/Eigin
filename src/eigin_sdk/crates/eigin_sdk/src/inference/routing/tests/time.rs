use super::{super::*, fixtures::*};

#[test]
fn fractional_pre_epoch_quarantine_expires_at_equality() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let router = ModelRouter::new();
    router.record(outcome("a", failed(RoutingFailure::TimedOut)), -300.5);
    assert_eq!(router.resolve(request(), -0.5001, -0.5001).model, "b");
    assert_eq!(router.resolve(request(), -0.5, -0.5).model, "a");
}

#[test]
fn fractional_pre_epoch_remote_evidence_expires_at_equality() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let router = ModelRouter::new();
    let mut observation = sample(11000.0, -2.5);
    observation.expires_at = -1.25;
    router.replace_remote_health("provider".into(), vec![remote(vec![observation])]);
    assert_eq!(router.resolve(request(), -2.5001, -2.5001).model, "a");
    assert_eq!(router.resolve(request(), -2.5, -2.5).model, "b");
    assert_eq!(router.resolve(request(), -1.2501, -1.2501).model, "b");
    assert_eq!(router.resolve(request(), -1.25, -1.25).model, "a");
}

#[test]
fn a_backwards_wall_clock_does_not_reset_session_health() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let router = ModelRouter::new();
    router.record(outcome("a", failed(RoutingFailure::ModelNotFound)), 100.0);
    assert_eq!(router.resolve(request(), 0.0, 0.0).model, "b");
    assert_eq!(router.resolve(request(), 3700.0, 3700.0).model, "b");
    assert_eq!(router.resolve(request(), 3700.1, 3700.1).model, "a");
}
