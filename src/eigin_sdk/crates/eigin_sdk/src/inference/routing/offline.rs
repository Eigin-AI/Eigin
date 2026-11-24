use super::{ModelRouter, equal, routing_model_facts, types::*};
use crate::clock::WallTime;

/// Host facts for an automatic offline detour. The first local provider is supplied in host order.
#[derive(Clone, Debug, uniffi::Record)]
pub struct RoutingOfflineInput {
    pub automatic: bool,
    pub current_provider_is_cloud: bool,
    pub local_ready: bool,
    pub local_inventory: Option<RoutingInventory>,
}

/// A transient local route; never replaces the persisted cloud selection.
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct RoutingOfflineRoute {
    pub provider_id: String,
    pub base_url: String,
    pub model: String,
}

pub(super) struct OfflineState {
    pub reachable: bool,
    pub failed: bool,
}

impl Default for OfflineState {
    fn default() -> Self {
        Self {
            reachable: true,
            failed: false,
        }
    }
}

#[uniffi::export]
impl ModelRouter {
    /// Records host reachability before awaiting inventory/health refreshes.
    pub fn record_reachability(&self, reachable: bool) {
        let mut state = self.state.lock().unwrap();
        if reachable && !state.offline.reachable {
            state.offline.failed = false;
        }
        state.offline.reachable = reachable;
    }

    /// Selects an offline detour without opening a cloud session or changing its affinity.
    pub fn offline_route(
        &self,
        input: RoutingOfflineInput,
        now: f64,
    ) -> Option<RoutingOfflineRoute> {
        let mut state = self.state.lock().unwrap();
        if !input.automatic
            || !input.current_provider_is_cloud
            || !input.local_ready
            || (state.offline.reachable && !state.offline.failed)
        {
            return None;
        }
        let mut inventory = input.local_inventory?;
        let offered = if inventory.enabled.is_empty() {
            inventory.available.clone()
        } else {
            inventory
                .enabled
                .iter()
                .filter(|id| inventory.available.iter().any(|a| equal(a, id)))
                .cloned()
                .collect()
        };
        if self.catalog.is_some() {
            inventory.models = routing_model_facts(offered.clone(), inventory.base_url.clone());
        }
        let model = offered.into_iter().min_by_key(|id| {
            inventory
                .models
                .iter()
                .find(|m| equal(&m.id, id))
                .and_then(|m| m.rank)
                .unwrap_or(u64::MAX)
        })?;
        state
            .local_health
            .activity(WallTime::from_unix_seconds(now));
        Some(RoutingOfflineRoute {
            provider_id: inventory.provider_id,
            base_url: inventory.base_url,
            model,
        })
    }
}
