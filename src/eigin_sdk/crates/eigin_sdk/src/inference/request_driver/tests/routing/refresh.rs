use super::*;

#[test]
fn replacement_captures_reasoning_demand_before_suspended_health_refresh() {
    let _diagnostics = diagnostics_lock();
    block_on(async {
        let mut input = route();
        input.inventory.as_mut().unwrap().models[2].supports_reasoning = true;
        let (router, platform, effects) = setup(input.clone());
        let (release, wait) = oneshot::channel();
        *platform.health_wait.lock().unwrap() = Some(wait);
        let mut replacement =
            effects.rank_replacement("a".into(), classified(RoutingFailure::TimedOut));
        assert!(futures::poll!(&mut replacement).is_pending());
        input.message_needs_reasoning = true;
        assert_eq!(router.resolve(input, 0.0, 0.0).model, "c");
        release.send(()).unwrap();
        assert_eq!(replacement.await.as_deref(), Some("b"));
    });
}

#[test]
fn replacement_uses_request_start_time_for_health_expiry() {
    let _diagnostics = diagnostics_lock();
    block_on(async {
        let mut input = route();
        input.inventory.as_mut().unwrap().models[0].supports_vision = false;
        input.requirements.needs_vision = true;
        let (_, platform, effects) = setup(input);
        *platform.clock.lock().unwrap() = 5.0;
        *platform.health.lock().unwrap() = vec![RoutingRemoteHealth {
            model: "b".into(),
            ttft: vec![RoutingHealthSample {
                value: 100_000.0,
                observed_at: 0.0,
                expires_at: 10.0,
                count: 10,
                probe: false,
            }],
            tps: vec![],
            failures: vec![],
        }];
        let (release, wait) = oneshot::channel();
        *platform.health_wait.lock().unwrap() = Some(wait);
        let mut replacement =
            effects.rank_replacement("a".into(), classified(RoutingFailure::PreAnswerBufferLimit));
        assert!(futures::poll!(&mut replacement).is_pending());
        *platform.clock.lock().unwrap() = 11.0;
        release.send(()).unwrap();
        assert_eq!(replacement.await.as_deref(), Some("c"));
    });
}

#[test]
fn refreshed_inventory_changes_retry_candidates_without_rewriting_dispatch_context() {
    let _diagnostics = diagnostics_lock();
    block_on(async {
        let mut input = route();
        input.inventory.as_mut().unwrap().available = vec!["a".into()];
        let (_, platform, effects) = setup(input);
        let mut updated = route().inventory.unwrap();
        updated.available = vec!["c".into()];
        updated.base_url = "https://changed.test".into();
        updated.models[2].reasoning_control = Some(CatalogReasoningControl {
            supported_efforts: vec![CatalogReasoningEffort::High],
            fast_effort: CatalogReasoningEffort::High,
            escalated_effort: CatalogReasoningEffort::High,
            default_effort: None,
        });
        *platform.inventory.lock().unwrap() = Some(updated);
        effects.refresh_catalog().await;
        assert_eq!(
            effects
                .rank_replacement("a".into(), classified(RoutingFailure::ModelNotFound))
                .await
                .as_deref(),
            Some("c")
        );
        // The original coordinator's dispatch closure retains its original request.
        assert_eq!(effects.prepare(2, "c".into()).await.unwrap(), None);
        assert_eq!(
            effects.options("a".into()).hedge.map(|hedge| hedge.model),
            None
        );
    });
}

#[test]
fn empty_health_refresh_clears_previous_remote_evidence() {
    let _diagnostics = diagnostics_lock();
    block_on(async {
        let (router, _, effects) = setup(route());
        router.replace_remote_health(
            "provider".into(),
            vec![RoutingRemoteHealth {
                model: "b".into(),
                ttft: vec![RoutingHealthSample {
                    value: 100_000.0,
                    observed_at: 0.0,
                    expires_at: 100.0,
                    count: 10,
                    probe: false,
                }],
                tps: vec![],
                failures: vec![],
            }],
        );
        assert_eq!(effects.options("a".into()).hedge.unwrap().model, "c");
        assert_eq!(
            effects
                .rank_replacement("a".into(), classified(RoutingFailure::TimedOut))
                .await
                .as_deref(),
            Some("b")
        );
    });
}
