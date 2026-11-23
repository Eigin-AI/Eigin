use super::{super::*, fixtures::*};

#[test]
fn reasoning_preference_orders_groups_before_catalog_rank() {
    use crate::model_catalog::{CatalogReasoningControl, CatalogReasoningEffort};
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    for (wants_reasoning, enabled, expected) in [
        (false, vec!["a", "b", "c"], "b"),
        (true, vec!["a", "b", "c"], "a"),
        (false, vec!["a", "c"], "c"),
        (true, vec!["b", "c"], "c"),
    ] {
        let router = ModelRouter::new();
        let mut input = request();
        input.conversation_id = Some("fresh".into());
        input.message_needs_reasoning = wants_reasoning;
        let inventory = input.inventory.as_mut().unwrap();
        inventory.models[0].supports_reasoning = true;
        inventory.available.push("c".into());
        inventory.enabled = enabled.into_iter().map(String::from).collect();
        let mut adjustable = model("c", 2);
        adjustable.supports_reasoning = true;
        adjustable.reasoning_control = Some(CatalogReasoningControl {
            supported_efforts: vec![CatalogReasoningEffort::None, CatalogReasoningEffort::High],
            fast_effort: CatalogReasoningEffort::None,
            escalated_effort: CatalogReasoningEffort::High,
            default_effort: None,
        });
        inventory.models.push(adjustable);
        assert_eq!(router.resolve(input, 0.0, 0.0).model, expected);
    }
}

#[test]
fn reasoning_lock_effort_and_fresh_conversations() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    use crate::model_catalog::{CatalogReasoningControl, CatalogReasoningEffort::*};
    let router = ModelRouter::new();
    let mut r = request();
    r.conversation_id = Some("conversation".into());
    let m = &mut r.inventory.as_mut().unwrap().models[0];
    m.supports_reasoning = true;
    m.reasoning_control = Some(CatalogReasoningControl {
        supported_efforts: vec![None, High],
        fast_effort: None,
        escalated_effort: High,
        default_effort: Option::None,
    });
    assert_eq!(router.resolve(r.clone(), 0.0, 0.0).model, "a");
    assert_eq!(router.reasoning_effort(r.clone(), "a".into()), Some(None));
    r.message_needs_reasoning = true;
    router.resolve(r.clone(), 1.0, 1.0);
    r.message_needs_reasoning = false;
    assert_eq!(router.reasoning_effort(r.clone(), "a".into()), Some(High));
    r.conversation_id = Some("new".into());
    assert_eq!(router.reasoning_effort(r, "a".into()), Some(None));
}

#[test]
fn fixed_reasoning_steps_up_and_locks_replacement_preference() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let router = ModelRouter::new();
    let mut r = request();
    r.conversation_id = Some("conversation".into());
    let inventory = r.inventory.as_mut().unwrap();
    inventory.models[1].supports_reasoning = true;
    inventory.available.push("c".into());
    let mut c = model("c", 2);
    c.supports_reasoning = true;
    inventory.models.push(c);
    assert_eq!(router.resolve(r.clone(), 0.0, 0.0), decision("a", None));
    r.message_needs_reasoning = true;
    assert_eq!(
        router.resolve(r.clone(), 1.0, 1.0),
        decision(
            "b",
            Some(RoutingChange::SteppedUp {
                previous: "a".into()
            })
        )
    );
    r.message_needs_reasoning = false;
    assert_eq!(router.resolve(r.clone(), 2.0, 2.0).model, "b");
    r.current_model = "b".into();
    assert_eq!(
        router
            .hedge_candidate(r.clone(), "b".into(), 2.0)
            .unwrap()
            .model,
        "c"
    );
    assert_eq!(
        router
            .replacement(r.clone(), RoutingFailure::TimedOut, Option::None, 2.0, 2.0)
            .unwrap()
            .model,
        "c"
    );
    let mut fresh = r.clone();
    fresh.conversation_id = Some("fresh".into());
    assert_eq!(
        router.resolve(fresh, 3.0, 3.0),
        decision(
            "a",
            Some(RoutingChange::SessionReset {
                previous: "b".into()
            })
        )
    );
    assert_eq!(
        router.resolve(r, 3602.1, 3602.1),
        decision(
            "a",
            Some(RoutingChange::SessionReset {
                previous: "b".into()
            })
        )
    );
}

#[test]
fn replacement_uses_demand_captured_before_an_interleaved_turn() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let router = ModelRouter::new();
    let mut r = request();
    r.conversation_id = Some("conversation".into());
    let i = r.inventory.as_mut().unwrap();
    i.available.push("c".into());
    let mut c = model("c", 2);
    c.supports_reasoning = true;
    i.models.push(c);
    let demand = router.replacement_demand(r.clone());
    let mut complex = r.clone();
    complex.message_needs_reasoning = true;
    assert_eq!(router.resolve(complex, 0.0, 0.0).model, "c");
    assert_eq!(
        router
            .replacement(r, RoutingFailure::TimedOut, Some(demand), 0.0, 1.0)
            .unwrap()
            .model,
        "b"
    );
}

#[test]
fn production_missing_provider_still_locks_reasoning() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let router = ModelRouter::with_catalog();
    let mut r = request();
    r.conversation_id = Some("conversation".into());
    r.current_model = "mistral-large-4".into();
    r.inventory = None;
    assert_eq!(router.resolve(r.clone(), 0.0, 0.0).model, "mistral-large-4");
    r.inventory = Some(RoutingInventory {
        provider_id: r.provider_id.clone(),
        base_url: "https://api.mistral.ai/v1".into(),
        available: vec!["mistral-large-4".into()],
        enabled: vec![],
        models: vec![],
    });
    assert_eq!(
        router.reasoning_effort(r, "mistral-large-4".into()),
        Some(crate::model_catalog::CatalogReasoningEffort::Medium)
    );
}
