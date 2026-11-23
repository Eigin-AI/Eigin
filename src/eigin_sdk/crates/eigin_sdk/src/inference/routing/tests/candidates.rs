use super::{super::*, fixtures::*};

#[test]
fn offered_enabled_and_equal_rank_order() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let router = ModelRouter::new();
    let mut r = request();
    r.conversation_id = Some("new".into());
    r.inventory.as_mut().unwrap().enabled = vec!["missing".into(), "b".into()];
    assert_eq!(router.resolve(r.clone(), 0.0, 0.0).model, "b");
    let i = r.inventory.as_mut().unwrap();
    i.enabled.clear();
    i.available.reverse();
    i.models[1].rank = Some(0);
    r.conversation_id = Some("another".into());
    assert_eq!(router.resolve(r, 0.0, 0.0).model, "b");
}

#[test]
fn resolution_can_relax_prompt_and_health_but_replacement_cannot() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let router = ModelRouter::new();
    let mut r = request();
    r.requirements.prompt_tokens = Some(1_000_000);
    assert_eq!(router.resolve(r.clone(), 0.0, 0.0).model, "a");
    assert!(
        router
            .replacement(
                r,
                RoutingFailure::ProviderOverloaded,
                Option::None,
                0.0,
                0.0
            )
            .is_none()
    );
    router.record(
        outcome("b", failed(RoutingFailure::ProviderOverloaded)),
        0.0,
    );
    assert_eq!(router.resolve(request(), 0.0, 0.0).model, "a");
    assert!(
        router
            .replacement(
                request(),
                RoutingFailure::PreAnswerBufferLimit,
                Option::None,
                0.0,
                0.0
            )
            .is_none()
    );
    assert!(router.can_satisfy(request(), 0.0)); // Capability queries also relax health.
}

#[test]
fn concessions_choose_vision_before_window_and_health_last() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let router = ModelRouter::new();
    let mut r = request();
    r.current_model = "unknown".into();
    r.requirements.needs_vision = true;
    r.requirements.prompt_tokens = Some(10_000);
    let inventory = r.inventory.as_mut().unwrap();
    inventory.models[0].context_window = 1000;
    inventory.models[1].supports_vision = false;
    assert_eq!(router.resolve(r.clone(), 0.0, 0.0).model, "b");
    router.record(outcome("b", failed(RoutingFailure::TimedOut)), 0.0);
    assert_eq!(router.resolve(r.clone(), 0.0, 0.0).model, "a");
    router.record(outcome("a", failed(RoutingFailure::TimedOut)), 0.0);
    assert_eq!(router.resolve(r.clone(), 0.0, 0.0).model, "a");
    assert!(
        router
            .replacement(
                r,
                RoutingFailure::PreAnswerBufferLimit,
                Option::None,
                0.0,
                0.0
            )
            .is_none()
    );
}

#[test]
fn tool_capability_is_hard_and_prompt_fit_uses_the_candidate_output_reserve() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let router = ModelRouter::new();
    let mut r = request();
    let inventory = r.inventory.as_mut().unwrap();
    inventory.models[0].supports_tools = false;
    inventory.models[1].context_window = 1000;
    inventory.models[1].max_output = Some(100);
    // (1000 - 100) * 3/4: paging policy reserves output and estimator headroom.
    r.requirements.prompt_tokens = Some(675);
    assert!(router.can_satisfy(r.clone(), 0.0));
    r.requirements.prompt_tokens = Some(676);
    assert!(!router.can_satisfy(r.clone(), 0.0));
    assert!(
        router
            .replacement(
                r.clone(),
                RoutingFailure::PreAnswerBufferLimit,
                None,
                0.0,
                0.0
            )
            .is_none()
    );
    r.inventory.as_mut().unwrap().models[1].supports_tools = false;
    r.current_model = "unknown".into();
    assert_eq!(router.resolve(r, 0.0, 0.0), decision("unknown", None));
}

#[test]
fn replacement_relaxes_vision_and_hedge_does_not_search_past_primary_only_match() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let router = ModelRouter::new();
    let mut r = request();
    r.requirements.needs_vision = true;
    r.inventory.as_mut().unwrap().models[1].supports_vision = false;
    assert!(router.hedge_candidate(r.clone(), "a".into(), 0.0).is_none());
    assert_eq!(
        router
            .replacement(r, RoutingFailure::TimedOut, Option::None, 0.0, 0.0)
            .unwrap()
            .model,
        "b"
    );
}

#[test]
fn pinned_unknown_and_non_model_failures() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let router = ModelRouter::new();
    let mut r = request();
    r.automatic = false;
    router.record(outcome("a", failed(RoutingFailure::ModelNotFound)), 0.0);
    assert_eq!(router.resolve(r.clone(), 0.0, 0.0), decision("a", None));
    assert!(
        router
            .replacement(r, RoutingFailure::ModelNotFound, Option::None, 0.0, 0.0)
            .is_none()
    );
    for failure in [RoutingFailure::Offline, RoutingFailure::NotTheModelsFault] {
        assert!(
            router
                .replacement(request(), failure, Option::None, 0.0, 0.0)
                .is_none()
        );
    }
    let mut r = request();
    r.current_model = "unknown".into();
    r.inventory.as_mut().unwrap().models.clear();
    assert_eq!(router.resolve(r, 0.0, 0.0), decision("unknown", None));
}

#[test]
fn production_facts_use_catalog_and_endpoint_controls() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let facts = routing_model_facts(
        vec!["mistral-large-4".into(), "unknown".into()],
        "https://api.mistral.ai/v1".into(),
    );
    assert_eq!(facts.len(), 1);
    assert!(facts[0].reasoning_control.is_some());
}
