use super::{
    candidates::Selection,
    diagnostics, equal,
    state::{RoutingState, decision},
    types::*,
};
use crate::clock::WallTime;

impl RoutingState {
    pub(super) fn choose_turn_model(
        &mut self,
        request: &RoutingRequest,
        inventory: &RoutingInventory,
        now: WallTime,
        decision_time: WallTime,
    ) -> RoutingDecision {
        let reset = self.open_session_if_idle(now);
        let fresh = self.is_new_conversation(request);
        let anchor = self.conversation_anchor(request).to_owned();
        let reasoning = request.message_needs_reasoning || self.reasoning.contains(&request.key());
        self.remember_reasoning_demand(request, reasoning);
        let candidates = self.candidates(request, inventory, now, reasoning, Selection::Turn);
        let Some(preferred) = candidates.first() else {
            diagnostics::event(
                "no eligible candidate; retaining current model",
                &request.current_model,
                &[],
            );
            return self.remember_route(request, decision(&request.current_model, None));
        };
        let route = if reset || fresh {
            preferred_route(preferred, &anchor)
        } else if can_keep_anchor(request, inventory, &anchor, &candidates) {
            decision(&anchor, None)
        } else {
            self.switch_model(
                inventory,
                &anchor,
                preferred,
                request.message_needs_reasoning,
                decision_time,
            )
        };
        self.remember_route(request, route)
    }

    fn switch_model(
        &mut self,
        inventory: &RoutingInventory,
        anchor: &str,
        preferred: &str,
        needs_reasoning: bool,
        now: WallTime,
    ) -> RoutingDecision {
        let stepped_up = needs_reasoning
            && inventory
                .model(anchor)
                .is_some_and(|m| !m.supports_reasoning)
            && self.healthy(inventory, anchor, now);
        let change = if stepped_up {
            RoutingChange::SteppedUp {
                previous: anchor.into(),
            }
        } else {
            self.change_reason(inventory, anchor, now)
        };
        decision(preferred, Some(change))
    }
}

fn preferred_route(preferred: &str, anchor: &str) -> RoutingDecision {
    if equal(preferred, anchor) {
        decision(anchor, None)
    } else {
        decision(
            preferred,
            Some(RoutingChange::SessionReset {
                previous: anchor.into(),
            }),
        )
    }
}

fn can_keep_anchor(
    request: &RoutingRequest,
    inventory: &RoutingInventory,
    anchor: &str,
    candidates: &[String],
) -> bool {
    candidates.iter().any(|m| equal(m, anchor))
        && (!request.message_needs_reasoning
            || inventory
                .model(anchor)
                .is_some_and(|m| m.supports_reasoning))
}
