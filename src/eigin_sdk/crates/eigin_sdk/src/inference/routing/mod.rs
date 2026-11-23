//! Stateful cloud selection. Hosts own inventory discovery, offline detours and persistence.
mod candidates;
mod diagnostics;
mod hedging;
mod identity;
mod local_health;
mod observations;
mod policy;
mod reasoning;
mod remote_health;
mod router;
mod selection;
mod state;
mod turn_selection;
mod types;

pub use candidates::routing_model_facts;
use identity::{equal, key};
pub use router::ModelRouter;
pub use types::*;

#[cfg(test)]
mod tests;
