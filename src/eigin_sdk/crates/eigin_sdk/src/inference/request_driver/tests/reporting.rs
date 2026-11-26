use super::*;
use crate::{
    clock::{ExecutionClock, testing::ManualClock},
    inference::{
        InferencePerformance,
        routing::{RoutingFailure, RoutingResult},
    },
};
use std::time::Duration;

fn performance(milliseconds: f64, tokens: f64) -> InferenceEvent {
    InferenceEvent::Performance {
        measurement: InferencePerformance {
            time_to_first_token_ms: Some(milliseconds),
            tokens_per_second: Some(tokens),
        },
    }
}

#[test]
fn successful_measurements_override_observed_text_but_failures_use_observed_time() {
    block_on(async {
        for succeeds in [true, false] {
            let host = effects(
                "winner",
                vec![text("answer"), text("later"), performance(125.0, 23.0)],
            );
            host.ranking.lock().unwrap().push_back("winner".into());
            host.streams.lock().unwrap()["winner"]
                .events
                .lock()
                .unwrap()
                .push_back(if succeeds {
                    Ok(Some(finish()))
                } else {
                    Err(RequestError::Classified {
                        error: InferenceError::InvalidData {
                            reason: "stream interrupted".into(),
                        },
                        failure: RoutingFailure::TimedOut,
                    })
                });
            let clock = Arc::new(ManualClock::default());
            let mut request = InferenceRequest::open_with_clock(
                options(),
                host.clone(),
                clock.now(),
                clock.clone(),
            )
            .await
            .unwrap();
            clock.advance(Duration::from_secs(2));
            let event = request.next().await.unwrap().unwrap();
            request.observe_output(&event);
            clock.advance(Duration::from_secs(1));
            loop {
                match request.next().await {
                    Ok(Some(event)) => request.observe_output(&event),
                    Ok(None) => {
                        assert!(succeeds);
                        break;
                    }
                    Err(_) => {
                        assert!(!succeeds);
                        break;
                    }
                }
            }
            let outcome = if succeeds {
                RoutingResult::Succeeded
            } else {
                RoutingResult::Failed {
                    failure: RoutingFailure::TimedOut,
                }
            };
            let report = request.report(outcome).unwrap();
            assert_eq!(report.model, "winner");
            assert_eq!(
                report.first_token_seconds,
                Some(if succeeds { 0.125 } else { 2.0 })
            );
            assert_eq!(report.tokens_per_second, succeeds.then_some(23.0));
            assert_eq!(host.reports.lock().unwrap().len(), 1);
        }
    });
}

#[test]
fn tool_only_output_uses_optional_provider_performance() {
    block_on(async {
        for measured in [false, true] {
            let mut events = vec![
                InferenceEvent::ToolCall {
                    call: InferenceToolCall {
                        id: "call".into(),
                        kind: "function".into(),
                        name: "lookup".into(),
                        arguments: "{}".into(),
                    },
                },
                text(""),
            ];
            if measured {
                events.push(performance(500.0, 9.0));
            }
            events.push(finish());
            let mut request = InferenceRequest::open(options(), effects("primary", events))
                .await
                .unwrap();
            while let Some(event) = request.next().await.unwrap() {
                request.observe_output(&event);
            }
            let report = request.report(RoutingResult::Succeeded).unwrap();
            assert_eq!(report.first_token_seconds, measured.then_some(0.5));
            assert_eq!(report.tokens_per_second, measured.then_some(9.0));
        }
    });
}

#[test]
fn exhausted_candidate_failure_is_deduplicated_but_cancellation_is_reported() {
    block_on(async {
        let host = Arc::new(Effects::default());
        let mut request = InferenceRequest::open(options(), host.clone())
            .await
            .unwrap();
        assert!(request.next().await.is_err());
        assert!(
            request
                .report(RoutingResult::Failed {
                    failure: RoutingFailure::ModelNotFound
                })
                .is_none()
        );
        assert!(host.reports.lock().unwrap().is_empty());
        let cancelled = request.report(RoutingResult::Cancelled).unwrap();
        assert_eq!(cancelled.first_token_seconds, None);
        assert_eq!(cancelled.tokens_per_second, None);
        assert_eq!(host.reports.lock().unwrap().len(), 1);
    });
}
