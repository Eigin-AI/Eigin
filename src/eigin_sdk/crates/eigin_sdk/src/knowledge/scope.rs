use std::collections::{HashMap, HashSet};

use firm_core::EntityId;

/// Scope metadata for a source the host has already authorized.
#[derive(Clone, Debug, uniffi::Record)]
pub struct KnowledgeSourceScope {
    pub source_id: String,
    pub path: String,
    pub space_id: Option<String>,
    pub agent_id: Option<String>,
}

/// Maps legacy source paths to Firm-normalized entity keys.
#[uniffi::export]
pub fn knowledge_entity_key(path: String) -> String {
    let stripped = path.replace("knowledge/", "").replace("bundled/", "");
    let stripped = stripped.strip_suffix(".firm").unwrap_or(&stripped);
    let Some((entity_type, id)) = stripped.split_once('/') else {
        return stripped.into();
    };
    let id = id.strip_prefix(&format!("{entity_type}.")).unwrap_or(id);
    EntityId::new(format!("{entity_type}.{id}")).to_string()
}

/// Selects shadow winners without expanding the host-authorized source set.
/// Matching space outranks matching agent; ties retain the first supplied row.
#[uniffi::export]
pub fn knowledge_select_source_ids(
    sources: Vec<KnowledgeSourceScope>,
    space_id: Option<String>,
    agent_id: Option<String>,
) -> Vec<String> {
    let mut winners: HashMap<String, (usize, u8)> = HashMap::new();
    for (index, source) in sources.iter().enumerate() {
        let score = u8::from(source.space_id.is_some() && source.space_id == space_id) * 2
            + u8::from(source.agent_id.is_some() && source.agent_id == agent_id);
        let key = knowledge_entity_key(source.path.clone());
        if winners
            .get(&key)
            .is_none_or(|(_, previous)| score > *previous)
        {
            winners.insert(key, (index, score));
        }
    }
    let indices: HashSet<_> = winners.values().map(|(index, _)| *index).collect();
    sources
        .into_iter()
        .enumerate()
        .filter_map(|(index, source)| indices.contains(&index).then_some(source.source_id))
        .collect()
}
