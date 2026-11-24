use super::{super::*, fixtures::*};

fn input() -> RoutingOfflineInput {
    RoutingOfflineInput {
        automatic: true,
        current_provider_is_cloud: true,
        local_ready: true,
        local_inventory: Some(RoutingInventory {
            provider_id: "local".into(),
            base_url: "local://gemma".into(),
            available: vec!["second".into(), "first".into()],
            enabled: vec![],
            models: vec![model("first", 0), model("second", 1)],
        }),
    }
}

#[test]
fn offline_selection_preserves_pinning_readiness_and_enabled_inventory() {
    let router = ModelRouter::new();
    assert!(router.offline_route(input(), 0.0).is_none());
    router.record_reachability(false);
    assert_eq!(router.offline_route(input(), 0.0).unwrap().model, "first");
    for variant in 0..5 {
        let mut i = input();
        match variant {
            0 => i.automatic = false,
            1 => i.current_provider_is_cloud = false,
            2 => i.local_ready = false,
            3 => i.local_inventory = None,
            _ => i.local_inventory.as_mut().unwrap().enabled = vec!["missing".into()],
        }
        assert!(router.offline_route(i, 0.0).is_none());
    }
    let mut i = input();
    i.local_inventory.as_mut().unwrap().enabled = vec!["second".into(), "missing".into()];
    assert_eq!(router.offline_route(i, 0.0).unwrap().model, "second");
}

#[test]
fn failures_are_remembered_until_success_or_path_recovery() {
    let router = ModelRouter::new();
    router.record(outcome("cloud", failed(RoutingFailure::Offline)), 0.0);
    router.record_reachability(true);
    assert!(router.offline_route(input(), 0.0).is_some());
    router.record(outcome("cloud", RoutingResult::Cancelled), 0.0);
    assert!(router.offline_route(input(), 0.0).is_some());
    router.record(
        outcome("cloud", failed(RoutingFailure::NotTheModelsFault)),
        0.0,
    );
    assert!(router.offline_route(input(), 0.0).is_some());
    router.record(outcome("cloud", RoutingResult::Succeeded), 0.0);
    assert!(router.offline_route(input(), 0.0).is_none());
    router.record(outcome("cloud", failed(RoutingFailure::Offline)), 0.0);
    router.record_reachability(false);
    router.record_reachability(true);
    assert!(router.offline_route(input(), 0.0).is_none());
    assert!(ModelRouter::new().offline_route(input(), 0.0).is_none());
}

#[test]
fn detours_keep_cloud_affinity_and_activity_without_affecting_replacement() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let router = ModelRouter::new();
    let mut r = request();
    r.conversation_id = Some("chat".into());
    router.resolve(r.clone(), 0.0, 0.0);
    assert_eq!(
        router
            .replacement(
                r.clone(),
                RoutingFailure::ProviderOverloaded,
                None,
                0.0,
                0.0
            )
            .unwrap()
            .model,
        "b"
    );
    router.record_reachability(false);
    assert!(router.offline_route(input(), 3500.0).is_some());
    assert!(
        router
            .replacement(r.clone(), RoutingFailure::Offline, None, 3500.0, 3500.0)
            .is_none()
    );
    router.record_reachability(true);
    assert_eq!(router.resolve(r.clone(), 4000.0, 4000.0).model, "b");
    assert_eq!(router.resolve(r, 7100.1, 7100.1).model, "a");
}

#[test]
fn tied_unknown_models_keep_offer_order_and_canonical_enabled_matching() {
    let router = ModelRouter::new();
    router.record_reachability(false);
    let mut i = input();
    let inventory = i.local_inventory.as_mut().unwrap();
    inventory.models.clear();
    assert_eq!(
        router.offline_route(i.clone(), 0.0).unwrap().model,
        "second"
    );
    let inventory = i.local_inventory.as_mut().unwrap();
    inventory.available = vec!["caf\u{e9}".into()];
    inventory.enabled = vec!["cafe\u{301}".into()];
    assert_eq!(router.offline_route(i, 0.0).unwrap().model, "cafe\u{301}");
}
