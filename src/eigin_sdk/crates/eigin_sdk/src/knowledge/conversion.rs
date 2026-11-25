// Adapted from 42futures/firm PR #53 (ecd9d9a), licensed AGPL-3.0.
//! Value conversion preserves the existing Firm FFI representation.

use super::types::*;
use firm_core::{Entity, EntityId, EntityType, FieldId, FieldValue, ReferenceValue};
use std::path::PathBuf;

// --- Conversions from firm_core types ---

impl From<&Entity> for KnowledgeEntity {
    fn from(entity: &Entity) -> Self {
        KnowledgeEntity {
            id: entity.id.to_string(),
            entity_type: entity.entity_type.to_string(),
            fields: entity
                .fields
                .iter()
                .map(|(id, value)| KnowledgeField {
                    name: id.to_string(),
                    value: KnowledgeFieldValue::from(value),
                })
                .collect(),
        }
    }
}

// --- Conversions to firm_core types ---

impl TryFrom<&KnowledgeEntity> for Entity {
    type Error = String;

    fn try_from(firm: &KnowledgeEntity) -> Result<Self, String> {
        let entity_id = EntityId::new(&firm.id);
        let entity_type = EntityType::new(&firm.entity_type);
        let mut entity = Entity::new(entity_id, entity_type);

        for field in &firm.fields {
            let value = FieldValue::try_from(&field.value)?;
            entity = entity.with_field(FieldId::new(&field.name), value);
        }

        Ok(entity)
    }
}

impl TryFrom<&KnowledgeFieldValue> for FieldValue {
    type Error = String;

    fn try_from(value: &KnowledgeFieldValue) -> Result<Self, String> {
        match value {
            KnowledgeFieldValue::Boolean { value } => Ok(FieldValue::Boolean(*value)),
            KnowledgeFieldValue::String { value } => Ok(FieldValue::String(value.clone())),
            KnowledgeFieldValue::Integer { value } => Ok(FieldValue::Integer(*value)),
            KnowledgeFieldValue::Float { value } => Ok(FieldValue::Float(*value)),
            KnowledgeFieldValue::Currency {
                amount,
                currency_code,
            } => {
                let decimal = rust_decimal::Decimal::from_str_exact(amount)
                    .map_err(|e| format!("Invalid currency amount '{}': {}", amount, e))?;
                let currency = iso_currency::Currency::from_code(currency_code)
                    .ok_or_else(|| format!("Invalid currency code '{}'", currency_code))?;
                Ok(FieldValue::Currency {
                    amount: decimal,
                    currency,
                })
            }
            KnowledgeFieldValue::EntityReference { entity_id } => Ok(FieldValue::Reference(
                ReferenceValue::Entity(EntityId::new(entity_id)),
            )),
            KnowledgeFieldValue::FieldReference {
                entity_id,
                field_id,
            } => Ok(FieldValue::Reference(ReferenceValue::Field(
                EntityId::new(entity_id),
                FieldId::new(field_id),
            ))),
            KnowledgeFieldValue::List { items } => {
                let values: Result<Vec<FieldValue>, String> =
                    items.iter().map(FieldValue::try_from).collect();
                Ok(FieldValue::List(values?))
            }
            KnowledgeFieldValue::DateTime { value } => {
                let dt = chrono::DateTime::parse_from_rfc3339(value)
                    .map_err(|e| format!("Invalid datetime '{}': {}", value, e))?;
                Ok(FieldValue::DateTime(dt))
            }
            KnowledgeFieldValue::Path { value } => Ok(FieldValue::Path(PathBuf::from(value))),
            KnowledgeFieldValue::Enum { value } => Ok(FieldValue::Enum(value.clone())),
        }
    }
}

// --- Conversions from firm_core types ---

impl From<&FieldValue> for KnowledgeFieldValue {
    fn from(value: &FieldValue) -> Self {
        match value {
            FieldValue::Boolean(v) => KnowledgeFieldValue::Boolean { value: *v },
            FieldValue::String(v) => KnowledgeFieldValue::String { value: v.clone() },
            FieldValue::Integer(v) => KnowledgeFieldValue::Integer { value: *v },
            FieldValue::Float(v) => KnowledgeFieldValue::Float { value: *v },
            FieldValue::Currency { amount, currency } => KnowledgeFieldValue::Currency {
                amount: amount.to_string(),
                currency_code: currency.code().to_string(),
            },
            FieldValue::Reference(ReferenceValue::Entity(entity_id)) => {
                KnowledgeFieldValue::EntityReference {
                    entity_id: entity_id.to_string(),
                }
            }
            FieldValue::Reference(ReferenceValue::Field(entity_id, field_id)) => {
                KnowledgeFieldValue::FieldReference {
                    entity_id: entity_id.to_string(),
                    field_id: field_id.to_string(),
                }
            }
            FieldValue::List(items) => KnowledgeFieldValue::List {
                items: items.iter().map(KnowledgeFieldValue::from).collect(),
            },
            FieldValue::DateTime(dt) => KnowledgeFieldValue::DateTime {
                value: dt.to_rfc3339(),
            },
            FieldValue::Path(p) => KnowledgeFieldValue::Path {
                value: p.to_string_lossy().into_owned(),
            },
            FieldValue::Enum(v) => KnowledgeFieldValue::Enum { value: v.clone() },
        }
    }
}
