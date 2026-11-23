use super::{ModelRouter, policy::*, types::*};
use crate::clock::WallTime;

#[uniffi::export]
impl ModelRouter {
    /// Replaces one provider's observations at the host's refresh points.
    pub fn replace_remote_health(
        &self,
        provider_id: String,
        observations: Vec<RoutingRemoteHealth>,
    ) {
        self.state
            .lock()
            .unwrap()
            .remote_health
            .replace(provider_id, observations);
    }

    /// Records an offline detour without changing cloud affinity or opening a session.
    pub fn mark_activity(&self, now: f64) {
        self.state
            .lock()
            .unwrap()
            .local_health
            .activity(WallTime::from_unix_seconds(now));
    }

    /// Applies completion evidence without retaining provider streams or errors.
    pub fn record(&self, outcome: RoutingOutcome, now: f64) {
        let mut state = self.state.lock().unwrap();
        let now = WallTime::from_unix_seconds(now);
        match outcome.result {
            RoutingResult::Cancelled => {}
            RoutingResult::Failed { failure } => {
                state.local_health.failure(&outcome.model, failure, now)
            }
            RoutingResult::Succeeded => {
                state.remote_health.success(&outcome, now);
                state.local_health.success(&outcome.model, now);
                if state.local_health.sample(
                    &outcome.model,
                    outcome
                        .first_token_seconds
                        .is_some_and(|v| v > SLOW_FIRST_TOKEN.as_secs_f64()),
                    outcome
                        .tokens_per_second
                        .is_some_and(|v| v < SLOW_THROUGHPUT),
                    now,
                ) {
                    state
                        .local_health
                        .quarantine(&outcome.model, now, SLOWNESS_QUARANTINE);
                }
            }
        }
    }
}
