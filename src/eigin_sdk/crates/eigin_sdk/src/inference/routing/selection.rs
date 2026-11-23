use super::{
    ModelRouter,
    candidates::Selection,
    diagnostics, equal,
    state::{RoutingState, decision},
    types::*,
};
use crate::clock::WallTime;

#[uniffi::export]
impl ModelRouter {
    /// Chooses a cloud model using request-start `now` and post-refresh `decision_time`.
    /// Both timestamps are wall-clock seconds since the Unix epoch.
    pub fn resolve(
        &self,
        mut request: RoutingRequest,
        now: f64,
        decision_time: f64,
    ) -> RoutingDecision {
        let mut state = self.state.lock().unwrap();
        self.resolve_model_facts(&mut request, &state, None);
        let Some(inventory) = request.inventory.as_ref().filter(|_| request.automatic) else {
            return self.retain_current_model(&mut state, &request);
        };
        state.choose_turn_model(
            &request,
            inventory,
            WallTime::from_unix_seconds(now),
            WallTime::from_unix_seconds(decision_time),
        )
    }

    /// Selects a same-provider replacement, preserving prepared-prompt fit and health.
    /// Supply pre-refresh demand when awaiting host observations; otherwise demand is read now.
    pub fn replacement(
        &self,
        mut request: RoutingRequest,
        failure: RoutingFailure,
        reasoning_demand: Option<bool>,
        now: f64,
        decision_time: f64,
    ) -> Option<RoutingDecision> {
        let mut state = self.state.lock().unwrap();
        self.resolve_model_facts(&mut request, &state, None);
        let inventory = request.inventory.as_ref().filter(|_| request.automatic)?;
        if !failure.blames_model() && failure != RoutingFailure::PreAnswerBufferLimit {
            return None;
        }
        let reasoning = reasoning_demand
            .unwrap_or_else(|| state.reasoning_demand(&request, &request.current_model));
        state.remember_reasoning_demand(&request, reasoning);
        let now = WallTime::from_unix_seconds(now);
        state
            .local_health
            .failure(&request.current_model, failure, now);
        let candidates =
            state.candidates(&request, inventory, now, reasoning, Selection::Replacement);
        let Some(next) = candidates
            .iter()
            .find(|m| !equal(m, &request.current_model))
        else {
            diagnostics::event("no eligible replacement", &request.current_model, &[]);
            return None;
        };
        let change = state.change_reason(
            inventory,
            &request.current_model,
            WallTime::from_unix_seconds(decision_time),
        );
        Some(state.remember_route(&request, decision(next, Some(change))))
    }

    /// Checks hard requirements without vision or prompt concessions.
    pub fn can_satisfy(&self, mut request: RoutingRequest, now: f64) -> bool {
        let mut state = self.state.lock().unwrap();
        self.resolve_model_facts(&mut request, &state, None);
        let Some(inventory) = &request.inventory else {
            return false;
        };
        if !request.automatic {
            return RoutingState::meets(inventory, &request.current_model, &request.requirements);
        }
        !state
            .candidates(
                &request,
                inventory,
                WallTime::from_unix_seconds(now),
                false,
                Selection::Capability,
            )
            .is_empty()
    }
}
