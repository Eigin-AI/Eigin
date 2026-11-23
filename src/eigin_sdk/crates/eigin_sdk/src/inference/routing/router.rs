use super::{
    RoutingDecision, RoutingRequest, key, routing_model_facts,
    state::{RoutingState, decision},
};
use crate::model_catalog::ModelCatalog;
use std::sync::{Arc, Mutex};

/// A shared routing session. Independent handles have independent health and affinity.
#[derive(Default, uniffi::Object)]
pub struct ModelRouter {
    pub(super) state: Mutex<RoutingState>,
    pub(super) catalog: Option<Arc<ModelCatalog>>,
}

#[uniffi::export]
impl ModelRouter {
    /// Creates a router using supplied inventory facts; retain it across turns and conversations.
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }

    /// Creates a production router that resolves model facts from the embedded catalog.
    #[uniffi::constructor]
    pub fn with_catalog() -> Arc<Self> {
        Arc::new(Self {
            state: Mutex::default(),
            catalog: Some(ModelCatalog::default_catalog()),
        })
    }
}

impl ModelRouter {
    pub(super) fn retain_current_model(
        &self,
        state: &mut RoutingState,
        request: &RoutingRequest,
    ) -> RoutingDecision {
        let route = state.remember_route(request, decision(&request.current_model, None));
        if request.automatic
            && let Some(id) = &request.conversation_id
            && let Some(catalog) = &self.catalog
            && catalog
                .lookup(route.model.clone())
                .is_some_and(|m| m.entry.supports_reasoning)
            && catalog
                .reasoning_control(route.model.clone(), String::new())
                .is_none()
        {
            state.reasoning.insert(key(id));
        }
        route
    }

    pub(super) fn resolve_model_facts(
        &self,
        request: &mut RoutingRequest,
        state: &RoutingState,
        extra: Option<&str>,
    ) {
        if self.catalog.is_none() {
            return;
        }
        let Some(inventory) = &mut request.inventory else {
            return;
        };
        let mut ids = inventory.available.clone();
        ids.extend(inventory.enabled.clone());
        ids.push(request.current_model.clone());
        if let Some(anchor) = request
            .conversation_id
            .as_ref()
            .and_then(|id| state.anchors.get(&key(id)))
        {
            ids.push(anchor.clone());
        }
        if let Some(model) = extra {
            ids.push(model.into());
        }
        inventory.models = routing_model_facts(ids, inventory.base_url.clone());
    }
}
