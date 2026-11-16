//! Coordinated synthetic requests for otherwise unobserved models.

use super::{
    Observation, Outcome, Source,
    measurement::StreamMeasurement,
    store::{StatusStore, now_ms},
};
use crate::{AppState, inference::upstream::UpstreamResponse};
use bytes::Bytes;
use futures::StreamExt;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::watch;

/// Run at most one probe at a time per replica, claiming shared wall-clock slots.
pub async fn run(
    state: Arc<AppState>,
    store: Arc<dyn StatusStore>,
    interval: Duration,
    mut shutdown: watch::Receiver<bool>,
) {
    let interval_ms = i64::try_from(interval.as_millis()).expect("bounded interval");
    let mut tick = tokio::time::interval(Duration::from_secs(60));
    tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    loop {
        tokio::select! {
            _ = shutdown.changed() => return,
            _ = tick.tick() => {}
        }
        let mut models: Vec<_> = state.canonical_models.values().collect();
        models.sort_by(|a, b| a.id.cmp(&b.id));
        for model in models {
            if *shutdown.borrow() {
                return;
            }
            let Some(client) = state.provider_clients.get(&model.provider) else {
                continue;
            };
            let Some(key) = state.provider_keys.get(&model.provider) else {
                continue;
            };
            let claimed = tokio::time::timeout(
                Duration::from_secs(5),
                store.claim_probe(&model.id, interval_ms),
            )
            .await;
            if !matches!(claimed, Ok(Ok(true))) {
                continue;
            }
            let observation = tokio::select! {
                _ = shutdown.changed() => return,
                observation = observe(model, client.as_ref(), key) => observation,
            };
            state.model_status.record(observation);
            // Spread a quiet catalog's requests instead of bursting at the slot edge.
            tokio::select! {
                _ = shutdown.changed() => return,
                _ = tokio::time::sleep(Duration::from_secs(1)) => {}
            }
        }
    }
}

/// Run one bounded synthetic request through the same measurement path as traffic.
pub async fn observe(
    model: &crate::inference::catalog::ModelConfig,
    client: &dyn crate::inference::upstream::UpstreamClient,
    key: &str,
) -> Observation {
    let started = Instant::now();
    let request = Bytes::from(serde_json::to_vec(&serde_json::json!({
        "model": model.upstream_id(),
        "messages": [{"role": "user", "content": "Count from one to twenty, separated by spaces."}],
        "stream": true,
        "stream_options": {"include_usage": true},
        "max_tokens": 1024
    })).expect("fixed probe request"));
    let probe = async {
        match client.chat_completions(request, key).await {
            Ok(UpstreamResponse::Stream(mut stream)) => {
                let mut measurement = StreamMeasurement::default();
                while let Some(chunk) = stream.next().await {
                    match chunk {
                        Ok(bytes) => measurement.observe(&bytes, started.elapsed()),
                        Err(_) => {
                            measurement.mark_failure();
                            break;
                        }
                    }
                }
                measurement.finish(model.id.clone(), Source::Probe, now_ms(), started.elapsed())
            }
            Ok(UpstreamResponse::Buffer(bytes)) => {
                outcome(&model.id, super::measurement::buffered_outcome(&bytes))
            }
            Err(crate::AppError::UpstreamStatus(429)) => outcome(&model.id, Outcome::Overloaded),
            Err(_) => outcome(&model.id, Outcome::UpstreamFailure),
        }
    };
    tokio::time::timeout(Duration::from_secs(30), probe)
        .await
        .unwrap_or_else(|_| outcome(&model.id, Outcome::Timeout))
}

fn outcome(model: &str, outcome: Outcome) -> Observation {
    Observation {
        model_id: model.into(),
        source: Source::Probe,
        observed_at_ms: now_ms(),
        outcome,
        ttft_ms: None,
        tps: None,
    }
}
