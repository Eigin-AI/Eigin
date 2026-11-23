use super::{super::*, fixtures::*};

// Same visible café: a precomposed é versus e followed by a combining accent.
const COMPOSED_MODEL: &str = "caf\u{e9}";
const DECOMPOSED_MODEL: &str = "cafe\u{301}";

#[test]
fn fresh_and_idle_reset_routes_preserve_canonically_equal_anchor_bytes() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    for (anchor, offered) in [
        (COMPOSED_MODEL, DECOMPOSED_MODEL),
        (DECOMPOSED_MODEL, COMPOSED_MODEL),
    ] {
        let router = ModelRouter::new();
        let mut r = request();
        r.conversation_id = Some("conversation".into());
        r.current_model = anchor.into();
        let inventory = r.inventory.as_mut().unwrap();
        inventory.available[0] = offered.into();
        inventory.models[0].id = offered.into();
        for now in [0.0, 3600.1] {
            let route = router.resolve(r.clone(), now, now);
            assert_eq!(route.model.as_bytes(), anchor.as_bytes());
            assert_eq!(route.change, None);
        }
        r.current_model = "unknown".into();
        let sticky = router.resolve(r, 3601.0, 3601.0);
        assert_eq!(sticky.model.as_bytes(), anchor.as_bytes());
        assert_eq!(sticky.change, None);
    }
}

#[test]
fn canonical_identifiers_share_health_without_rewriting_selected_ids() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let router = ModelRouter::new();
    let mut r = request();
    let i = r.inventory.as_mut().unwrap();
    i.models[0].id = COMPOSED_MODEL.into();
    i.available[0] = DECOMPOSED_MODEL.into();
    r.current_model = "unknown".into();
    assert_eq!(router.resolve(r.clone(), 0.0, 0.0).model, DECOMPOSED_MODEL);
    router.record(
        outcome(COMPOSED_MODEL, failed(RoutingFailure::ModelNotFound)),
        0.0,
    );
    assert_eq!(router.resolve(r, 0.0, 0.0).model, "b");
}
