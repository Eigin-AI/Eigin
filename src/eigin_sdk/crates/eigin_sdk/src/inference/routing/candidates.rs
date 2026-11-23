use super::{equal, policy::ASSUMED_OUTPUT_RESERVE, state::RoutingState, types::*};
use crate::clock::WallTime;
use crate::{context::default_paging_policy, model_catalog::ModelCatalog};

impl RoutingInventory {
    pub(super) fn model(&self, id: &str) -> Option<&RoutingModel> {
        self.models.iter().find(|m| equal(&m.id, id))
    }

    pub(super) fn offer(&self) -> Vec<&str> {
        if self.enabled.is_empty() {
            return self.available.iter().map(String::as_str).collect();
        }
        self.enabled
            .iter()
            .filter(|id| self.available.iter().any(|available| equal(available, id)))
            .map(String::as_str)
            .collect()
    }
}

impl RoutingModel {
    fn meets(&self, requirements: &RoutingRequirements) -> bool {
        (!requirements.needs_tools || self.supports_tools)
            && (!requirements.needs_vision || self.supports_vision)
            && requirements.prompt_tokens.is_none_or(|tokens| {
                tokens
                    <= default_paging_policy(
                        self.context_window,
                        self.max_output.unwrap_or(ASSUMED_OUTPUT_RESERVE),
                    )
                    .maximum_tokens
            })
    }

    fn matches_reasoning_preference(&self, wants_reasoning: bool) -> bool {
        self.reasoning_control.is_some() || self.supports_reasoning == wants_reasoning
    }
}

pub(super) enum Selection {
    Turn,
    Replacement,
    Capability,
}

impl Selection {
    fn relax_next(&self, requirements: &mut RoutingRequirements) -> bool {
        if !matches!(self, Self::Capability) && requirements.needs_vision {
            requirements.needs_vision = false;
            return true;
        }
        if matches!(self, Self::Turn) && requirements.prompt_tokens.is_some() {
            requirements.prompt_tokens = None;
            return true;
        }
        false
    }
}

impl RoutingState {
    pub(super) fn healthy(
        &mut self,
        inventory: &RoutingInventory,
        model: &str,
        now: WallTime,
    ) -> bool {
        self.local_health.healthy(model, now)
            && self
                .remote_health
                .reason(&inventory.provider_id, model, now)
                .is_none()
    }

    pub(super) fn candidates(
        &mut self,
        request: &RoutingRequest,
        inventory: &RoutingInventory,
        now: WallTime,
        reasoning: bool,
        selection: Selection,
    ) -> Vec<String> {
        let mut ranked: Vec<_> = inventory
            .offer()
            .into_iter()
            .filter_map(|id| inventory.model(id).map(|m| (id, m)))
            .collect();
        // Matching reasoning preference sorts first; catalog rank orders each group.
        ranked.sort_by_key(|(_, m)| {
            (
                !m.matches_reasoning_preference(reasoning),
                m.rank.unwrap_or(u64::MAX),
            )
        });
        let mut requirements = request.requirements;
        let mut step = 0;
        loop {
            let matches: Vec<_> = ranked
                .iter()
                .filter(|(id, m)| m.meets(&requirements) && self.healthy(inventory, id, now))
                .map(|(id, _)| (*id).to_owned())
                .collect();
            if !matches.is_empty() {
                if step > 0 {
                    super::diagnostics::event(
                        "routing requirements relaxed",
                        &matches[0],
                        &[("concession_step", step as f64)],
                    );
                }
                return matches;
            }
            if !selection.relax_next(&mut requirements) {
                break;
            }
            step += 1;
        }
        if matches!(selection, Selection::Replacement) {
            return vec![];
        }
        let matches: Vec<_> = ranked
            .into_iter()
            .filter(|(id, m)| m.meets(&requirements) && !self.local_health.retired(id))
            .map(|(id, _)| id.to_owned())
            .collect();
        if let Some(model) = matches.first() {
            super::diagnostics::event("all eligible models unhealthy; trying anyway", model, &[]);
        }
        matches
    }

    pub(super) fn meets(
        inventory: &RoutingInventory,
        model: &str,
        requirements: &RoutingRequirements,
    ) -> bool {
        inventory
            .model(model)
            .is_some_and(|m| m.meets(requirements))
    }
}

/// Resolves routing facts with the SDK's production catalog and endpoint policy.
#[uniffi::export]
pub fn routing_model_facts(model_ids: Vec<String>, base_url: String) -> Vec<RoutingModel> {
    let catalog = ModelCatalog::default_catalog();
    model_ids
        .into_iter()
        .filter_map(|id| {
            let entry = catalog.lookup(id.clone())?.entry;
            Some(RoutingModel {
                rank: catalog.preference_rank(id.clone()),
                reasoning_control: catalog.reasoning_control(id.clone(), base_url.clone()),
                id,
                supports_tools: entry.supports_tool_call,
                supports_vision: entry.supports_vision,
                supports_reasoning: entry.supports_reasoning,
                context_window: entry.context_window,
                max_output: entry.max_output,
            })
        })
        .collect()
}
