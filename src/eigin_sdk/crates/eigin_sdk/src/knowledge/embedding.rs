use unicode_segmentation::UnicodeSegmentation;

use super::{KnowledgeEntity, KnowledgeFieldValue};

/// Selects entity text for host-provided embedding generation.
#[uniffi::export]
pub fn knowledge_embedding_text(entity: KnowledgeEntity) -> String {
    let string = |name: &str| {
        entity
            .fields
            .iter()
            .find(|field| field.name == name)
            .and_then(|field| match &field.value {
                KnowledgeFieldValue::String { value } => Some(value.as_str()),
                _ => None,
            })
    };
    let enumeration = |name: &str| {
        entity
            .fields
            .iter()
            .find(|field| field.name == name)
            .and_then(|field| match &field.value {
                KnowledgeFieldValue::Enum { value } => Some(value.as_str()),
                _ => None,
            })
    };
    match entity.entity_type.as_str() {
        "actor" | "thing" => {
            let name = string("name").unwrap_or(&entity.id);
            let category = enumeration(if entity.entity_type == "actor" {
                "type"
            } else {
                "category"
            });
            category.map_or_else(|| name.into(), |category| format!("{name}, {category}"))
        }
        "fact" => {
            let claim = string("claim").unwrap_or(&entity.id);
            match string("name").filter(|name| !name.is_empty()) {
                Some(name) => format!("{name}: {claim}"),
                None => claim.into(),
            }
        }
        "output" => {
            let name = string("name").unwrap_or(&entity.id);
            let content: String = string("content")
                .unwrap_or("")
                .graphemes(true)
                .take(500)
                .collect();
            if content.is_empty() {
                name.into()
            } else {
                format!("{name}: {content}")
            }
        }
        "note" => string("content").unwrap_or(&entity.id).into(),
        _ => entity
            .fields
            .iter()
            .filter_map(|field| match &field.value {
                KnowledgeFieldValue::String { value } => Some(value.as_str()),
                _ => None,
            })
            .collect::<Vec<_>>()
            .join(" "),
    }
}
