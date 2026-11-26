use super::*;

#[test]
fn request_uses_sdk_replacement_and_preserves_refresh_before_health() {
    let _diagnostics = diagnostics_lock();
    block_on(async {
        let (router, platform, effects) = setup(route());
        platform
            .execution
            .streams
            .lock()
            .unwrap()
            .insert("b".into(), Stream::new(vec![text("answer"), finish()]));
        let mut request = effects.start("a".into()).await.unwrap();
        assert_eq!(request.next().await.unwrap(), Some(text("answer")));
        assert_eq!(request.attempts().winning_model(), "b");
        assert!(request.attempts().retry_won());
        assert_eq!(*platform.execution.opens.lock().unwrap(), ["a", "b"]);
        assert_eq!(
            *platform.log.lock().unwrap(),
            [
                "validate:a",
                "catalog:provider",
                "health:provider",
                "validate:b"
            ]
        );
        assert_eq!(
            router
                .hedge_candidate(route(), "b".into(), 0.0)
                .unwrap()
                .model,
            "c"
        );
    });
}

#[test]
fn dispatch_uses_sdk_reasoning_effort_after_host_validation() {
    let _diagnostics = diagnostics_lock();
    block_on(async {
        let mut input = route();
        let model = &mut input.inventory.as_mut().unwrap().models[0];
        model.supports_reasoning = true;
        model.reasoning_control = Some(CatalogReasoningControl {
            supported_efforts: vec![CatalogReasoningEffort::None, CatalogReasoningEffort::High],
            fast_effort: CatalogReasoningEffort::None,
            escalated_effort: CatalogReasoningEffort::High,
            default_effort: None,
        });
        input.message_needs_reasoning = true;
        let (_, platform, effects) = setup(input);
        platform
            .execution
            .streams
            .lock()
            .unwrap()
            .insert("a".into(), Stream::new(vec![text("answer")]));
        let mut request = effects.start("a".into()).await.unwrap();
        request.next().await.unwrap();
        assert_eq!(
            *platform.efforts.lock().unwrap(),
            [("a".into(), Some(CatalogReasoningEffort::High))]
        );
        assert_eq!(*platform.log.lock().unwrap(), ["validate:a"]);
    });
}

#[test]
fn pinned_and_local_requests_do_not_refresh_or_select_replacements() {
    let _diagnostics = diagnostics_lock();
    block_on(async {
        for local in [false, true] {
            let mut input = route();
            input.automatic = false;
            let router = ModelRouter::new();
            let platform = Arc::new(Platform::default());
            let effects = RoutedRequestEffects::new(
                router,
                platform.clone(),
                "provider".into(),
                local,
                Some(input),
            );
            let options = effects.options("a".into());
            assert!(options.hedge.is_none());
            assert_eq!(options.local, local);
            assert_eq!(
                effects
                    .rank_replacement("a".into(), classified(RoutingFailure::TimedOut))
                    .await,
                None
            );
            assert_eq!(effects.prepare(0, "a".into()).await.unwrap(), None);
            assert_eq!(*platform.log.lock().unwrap(), ["validate:a"]);
        }
    });
}

#[test]
fn explicit_failure_classification_overrides_identical_http_details() {
    let _diagnostics = diagnostics_lock();
    block_on(async {
        for (failure, expected) in [
            (RoutingFailure::ProviderOverloaded, Some("b")),
            (RoutingFailure::NotTheModelsFault, None),
            (RoutingFailure::Offline, None),
        ] {
            let (_, _, effects) = setup(route());
            assert_eq!(
                effects
                    .rank_replacement("a".into(), classified(failure))
                    .await
                    .as_deref(),
                expected
            );
        }
        let (_, _, effects) = setup(route());
        assert_eq!(
            effects
                .rank_replacement(
                    "a".into(),
                    InferenceError::Http {
                        status: 503,
                        body: None
                    }
                    .into()
                )
                .await,
            None
        );
        let missing = RequestError::Classified {
            error: InferenceError::Http {
                status: 404,
                body: Some("model not found".into()),
            },
            failure: RoutingFailure::NotTheModelsFault,
        };
        assert!(!missing.missing_model());
    });
}

#[test]
fn hedge_planning_and_loser_health_share_the_router_across_requests() {
    let _diagnostics = diagnostics_lock();
    let (router, _, effects) = setup(route());
    let first = effects.options("a".into()).hedge.unwrap();
    assert_eq!(first.model, "b");
    assert_eq!(first.delay_ms, 6000);
    for _ in 0..3 {
        effects.record_loser("a".into(), 10_000);
    }
    let next = effects.options("a".into()).hedge.unwrap();
    assert_eq!(next.model, "b");
    assert_eq!(router.resolve(route(), 0.0, 0.0).model, "b");
    // Quarantine clears slow samples, so its hedge delay returns to the default.
    assert_eq!(next.delay_ms, first.delay_ms);
}

#[test]
fn accepted_output_report_updates_shared_router_measurements() {
    let _diagnostics = diagnostics_lock();
    block_on(async {
        let router = ModelRouter::new();
        let platform = Arc::new(Platform::default());
        for expected_delay in [6.0, 3.0] {
            platform.execution.streams.lock().unwrap().insert(
                "b".into(),
                Stream::new(vec![
                    text("answer"),
                    InferenceEvent::Performance {
                        measurement: crate::inference::InferencePerformance {
                            time_to_first_token_ms: Some(11_000.0),
                            tokens_per_second: Some(50.0),
                        },
                    },
                    finish(),
                ]),
            );
            let mut input = route();
            input.current_model = "b".into();
            let effects = RoutedRequestEffects::new(
                router.clone(),
                platform.clone(),
                "provider".into(),
                false,
                Some(input),
            );
            let mut request = effects.start("b".into()).await.unwrap();
            while let Some(event) = request.next().await.unwrap() {
                request.observe_output(&event);
            }
            let report = request.report(RoutingResult::Succeeded).unwrap();
            assert_eq!(report.model, "b");
            assert_eq!(report.first_token_seconds, Some(11.0));
            assert_eq!(router.hedge_delay("b".into()), expected_delay);
        }
    });
}

#[test]
fn buffer_overflow_retries_without_quarantining_original_model() {
    let _diagnostics = diagnostics_lock();
    block_on(async {
        let (router, platform, effects) = setup(route());
        platform.execution.streams.lock().unwrap().extend([
            (
                "a".into(),
                Stream::new(vec![InferenceEvent::ProviderMetadata {
                    values: HashMap::from([("status".into(), "x".repeat(1024))]),
                }]),
            ),
            ("b".into(), Stream::new(vec![text("replacement"), finish()])),
        ]);
        let mut input = effects.options("a".into());
        input.max_buffered_bytes = 256;
        let mut request = InferenceRequest::open(input, effects).await.unwrap();
        assert_eq!(request.next().await.unwrap(), Some(text("replacement")));
        assert_eq!(request.attempts().winning_model(), "b");
        assert_eq!(*platform.execution.opens.lock().unwrap(), ["a", "b"]);
        let mut fresh = route();
        fresh.conversation_id = Some("fresh".into());
        assert_eq!(router.resolve(fresh, 0.0, 0.0).model, "a");
    });
}
