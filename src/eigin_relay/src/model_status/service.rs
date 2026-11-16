//! Bounded asynchronous recording and cached status responses.

use super::{
    Observation, StatusResponse,
    store::{StatusStore, now_ms},
};
use axum::{Json, extract::State};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, RwLock};
use std::time::Duration;
use tokio::sync::mpsc;

/// Nonblocking inference-side recorder and cached endpoint snapshot.
#[derive(Clone)]
pub struct ModelStatusService {
    sender: Option<mpsc::Sender<Observation>>,
    dropped: Arc<AtomicU64>,
    cache: Arc<RwLock<StatusResponse>>,
}

impl Default for ModelStatusService {
    fn default() -> Self {
        Self {
            sender: None,
            dropped: Arc::new(AtomicU64::new(0)),
            cache: Arc::new(RwLock::new(StatusResponse::aggregate(
                [],
                &[],
                now_ms(),
                900_000,
            ))),
        }
    }
}

impl ModelStatusService {
    /// Start bounded recording and minute-based rolling aggregation.
    /// Dropping all service handles stops the worker after queued writes finish.
    pub fn start(
        store: Arc<dyn StatusStore>,
        models: Vec<String>,
        lifetime: Duration,
    ) -> (Self, tokio::task::JoinHandle<()>) {
        let lifetime_ms = i64::try_from(lifetime.as_millis()).expect("bounded health interval");
        assert!(lifetime_ms > 0);
        let (sender, mut receiver) = mpsc::channel::<Observation>(256);
        let cache = Arc::new(RwLock::new(StatusResponse::aggregate(
            models.clone(),
            &[],
            now_ms(),
            lifetime_ms,
        )));
        let service = Self {
            sender: Some(sender),
            dropped: Arc::new(AtomicU64::new(0)),
            cache: cache.clone(),
        };
        let task = tokio::spawn(async move {
            let mut refresh = tokio::time::interval(Duration::from_secs(60));
            refresh.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
            loop {
                tokio::select! {
                    sample = receiver.recv() => {
                        let Some(sample) = sample else { break; };
                        match tokio::time::timeout(Duration::from_secs(5), store.record(sample)).await {
                            Ok(Ok(())) => {},
                            _ => tracing::warn!("model observation write failed or timed out"),
                        }
                    }
                    _ = refresh.tick() => {
                        let now = now_ms();
                        match tokio::time::timeout(Duration::from_secs(5), store.observations(now - lifetime_ms)).await {
                            Ok(Ok(samples)) => {
                                *cache.write().expect("status cache lock") = StatusResponse::aggregate(models.clone(), &samples, now, lifetime_ms);
                            }
                            _ => tracing::warn!("model status refresh failed or timed out"),
                        }
                    }
                }
            }
        });
        (service, task)
    }

    /// Queue an observation without delaying response delivery or billing.
    pub fn record(&self, observation: Observation) {
        if let Some(sender) = &self.sender {
            if sender.try_send(observation).is_err() {
                let dropped = self.dropped.fetch_add(1, Ordering::Relaxed) + 1;
                if dropped.is_power_of_two() {
                    tracing::warn!(
                        dropped,
                        "model observations dropped: recorder unavailable or full"
                    );
                }
            }
        }
    }

    /// Read the cached snapshot without any database or provider calls.
    pub fn snapshot(&self) -> StatusResponse {
        self.cache.read().expect("status cache lock").clone()
    }
}

/// Key-authenticated status endpoint; wallet authentication is unnecessary.
pub async fn handle(State(state): State<Arc<crate::AppState>>) -> Json<StatusResponse> {
    let mut snapshot = state.model_status.snapshot();
    // Anchor client clock-skew correction to serving time, while observation
    // timestamps and expiry remain those of the cached evidence.
    snapshot.generated_at = StatusResponse::aggregate([], &[], now_ms(), 1).generated_at;
    Json(snapshot)
}
