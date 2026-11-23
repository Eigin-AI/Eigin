use super::{ModelRouter, candidates::Selection, equal, policy::*, state::decision, types::*};
use crate::clock::WallTime;

#[uniffi::export]
impl ModelRouter {
    /// Selects a runner-up; the attempt controller authorizes and schedules its dispatch.
    pub fn hedge_candidate(
        &self,
        mut request: RoutingRequest,
        model: String,
        now: f64,
    ) -> Option<RoutingDecision> {
        let mut state = self.state.lock().unwrap();
        self.resolve_model_facts(&mut request, &state, Some(&model));
        let inventory = request.inventory.as_ref().filter(|_| request.automatic)?;
        let reasoning = state.reasoning_demand(&request, &model);
        state.remember_reasoning_demand(&request, reasoning);
        state
            .candidates(
                &request,
                inventory,
                WallTime::from_unix_seconds(now),
                reasoning,
                Selection::Turn,
            )
            .into_iter()
            .find(|m| !equal(m, &model))
            .map(|m| decision(&m, None))
    }

    /// Patience in seconds, derived from recent slow first-token samples.
    pub fn hedge_delay(&self, model: String) -> f64 {
        let delay = if self.state.lock().unwrap().local_health.slow_samples(&model)
            >= SLOW_SAMPLES_FOR_SHORT_HEDGE
        {
            SLOW_MODEL_HEDGE_DELAY
        } else {
            HEDGE_DELAY
        };
        delay.as_secs_f64()
    }

    /// Records a silent hedge loser; repeated slow samples quarantine the model.
    pub fn record_hedge_loss(&self, model: String, now: f64) {
        let mut state = self.state.lock().unwrap();
        let now = WallTime::from_unix_seconds(now);
        state.local_health.sample(&model, true, false, now);
        if state.local_health.slow_samples(&model) >= SLOW_SAMPLES_FOR_SHORT_HEDGE {
            state
                .local_health
                .quarantine(&model, now, SLOWNESS_QUARANTINE);
        }
    }
}
