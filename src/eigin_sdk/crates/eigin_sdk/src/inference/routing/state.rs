use super::{equal, key, local_health::LocalHealth, remote_health::RemoteHealth, types::*};
use crate::clock::WallTime;
use std::collections::{HashMap, HashSet};

#[derive(Default)]
pub(super) struct RoutingState {
    pub local_health: LocalHealth,
    pub remote_health: RemoteHealth,
    pub anchors: HashMap<String, String>,
    pub reasoning: HashSet<String>,
}

impl RoutingRequest {
    pub(super) fn key(&self) -> String {
        key(self.conversation_id.as_deref().unwrap_or(&self.provider_id))
    }
}

impl RoutingState {
    pub(super) fn open_session_if_idle(&mut self, now: WallTime) -> bool {
        if !self.local_health.open_session(now) {
            return false;
        }
        self.anchors.clear();
        self.reasoning.clear();
        self.remote_health.reset();
        true
    }

    pub(super) fn is_new_conversation(&self, request: &RoutingRequest) -> bool {
        request
            .conversation_id
            .as_ref()
            .is_some_and(|id| !self.anchors.contains_key(&key(id)))
    }

    pub(super) fn conversation_anchor<'a>(&'a self, request: &'a RoutingRequest) -> &'a str {
        request
            .conversation_id
            .as_ref()
            .and_then(|id| self.anchors.get(&key(id)))
            .unwrap_or(&request.current_model)
    }

    pub(super) fn remember_reasoning_demand(&mut self, request: &RoutingRequest, reasoning: bool) {
        if reasoning {
            self.reasoning.insert(request.key());
        }
    }

    pub(super) fn reasoning_demand(&self, request: &RoutingRequest, model: &str) -> bool {
        request.message_needs_reasoning
            || self.reasoning.contains(&request.key())
            || request
                .inventory
                .as_ref()
                .and_then(|i| i.model(model))
                .is_some_and(|m| m.reasoning_control.is_none() && m.supports_reasoning)
    }

    pub(super) fn remember_route(
        &mut self,
        request: &RoutingRequest,
        route: RoutingDecision,
    ) -> RoutingDecision {
        if request.automatic
            && let Some(id) = &request.conversation_id
        {
            self.anchors.insert(key(id), route.model.clone());
            if request
                .inventory
                .as_ref()
                .and_then(|i| i.model(&route.model))
                .is_some_and(|m| m.reasoning_control.is_none() && m.supports_reasoning)
            {
                self.reasoning.insert(key(id));
            }
        }
        route
    }

    pub(super) fn change_reason(
        &mut self,
        inventory: &RoutingInventory,
        model: &str,
        now: WallTime,
    ) -> RoutingChange {
        if !inventory.available.iter().any(|m| equal(m, model)) || self.local_health.retired(model)
        {
            RoutingChange::ModelRetired {
                previous: model.into(),
            }
        } else {
            RoutingChange::ModelDegraded {
                previous: model.into(),
                reason: self
                    .remote_health
                    .reason(&inventory.provider_id, model, now)
                    .unwrap_or(RoutingDegradation::Errors),
            }
        }
    }
}

pub(super) fn decision(model: &str, change: Option<RoutingChange>) -> RoutingDecision {
    RoutingDecision {
        model: model.into(),
        change,
    }
}
