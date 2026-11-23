use super::{ModelRouter, types::*};
use crate::model_catalog::CatalogReasoningEffort;

#[uniffi::export]
impl ModelRouter {
    /// Snapshots replacement demand before the host awaits a remote-health refresh.
    pub fn replacement_demand(&self, mut request: RoutingRequest) -> bool {
        let state = self.state.lock().unwrap();
        self.resolve_model_facts(&mut request, &state, None);
        state.reasoning_demand(&request, &request.current_model)
    }

    /// Chooses effort for an adjustable candidate using the conversation's reasoning lock.
    pub fn reasoning_effort(
        &self,
        mut request: RoutingRequest,
        model: String,
    ) -> Option<CatalogReasoningEffort> {
        if !request.automatic {
            return None;
        }
        let state = self.state.lock().unwrap();
        self.resolve_model_facts(&mut request, &state, Some(&model));
        let control = request
            .inventory
            .as_ref()?
            .model(&model)?
            .reasoning_control
            .as_ref()?;
        Some(
            if request.message_needs_reasoning || state.reasoning.contains(&request.key()) {
                control.escalated_effort
            } else {
                control.fast_effort
            },
        )
    }
}
