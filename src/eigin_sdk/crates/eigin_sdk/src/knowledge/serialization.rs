use std::path::{Component, Path, PathBuf};

use chrono::Timelike;
use firm_core::{Entity, FieldValue, compose_entity_id};
use firm_lang::{generate::generate_dsl, parser::dsl::parse_source};

use super::{KnowledgeEntity, KnowledgeError, paths};

pub(super) fn generate(
    entity: KnowledgeEntity,
    source_path: String,
) -> Result<String, KnowledgeError> {
    let source_path = paths::normalize(&source_path)?;
    let mut expected = Entity::try_from(&entity).map_err(invalid)?;
    if !expected.id.to_string().contains('.') {
        expected.id =
            compose_entity_id(&expected.entity_type.to_string(), &expected.id.to_string());
    }
    let mut serialized = expected.clone();
    let parent = Path::new(&source_path).parent().unwrap_or(Path::new(""));
    for (_, value) in &mut serialized.fields {
        make_paths_source_relative(value, parent);
    }
    let content = generate_dsl(&[serialized]);
    let parsed = parse_source(content.clone(), Some(source_path.into()))
        .map_err(|error| invalid(error.to_string()))?;
    if parsed.has_error() {
        return Err(invalid(
            "Typed values cannot be represented by the current Firm syntax",
        ));
    }
    let entities = parsed.entities();
    if entities.len() != 1 {
        return Err(invalid("Generated source must contain exactly one entity"));
    }
    let actual = Entity::try_from(&entities[0]).map_err(|error| invalid(error.to_string()))?;
    if actual.id != expected.id
        || actual.entity_type != expected.entity_type
        || actual.fields.len() != expected.fields.len()
    {
        return Err(invalid(
            "Entity identity or fields changed during source generation",
        ));
    }
    for ((name, value), (actual_name, actual_value)) in expected.fields.iter().zip(&actual.fields) {
        if name != actual_name || !same_value(value, actual_value) {
            return Err(invalid(format!(
                "Field {name} cannot round-trip through the current Firm syntax"
            )));
        }
    }
    Ok(content)
}

fn invalid(message: impl Into<String>) -> KnowledgeError {
    KnowledgeError::InvalidEntity {
        message: message.into(),
    }
}

fn make_paths_source_relative(value: &mut FieldValue, parent: &Path) {
    match value {
        FieldValue::Path(path) if path.is_relative() => {
            let target = components(path);
            let base = components(parent);
            let common = target.iter().zip(&base).take_while(|(a, b)| a == b).count();
            let mut relative = PathBuf::new();
            for _ in common..base.len() {
                relative.push("..");
            }
            for part in &target[common..] {
                relative.push(part.as_os_str());
            }
            *path = relative;
        }
        FieldValue::List(items) => items
            .iter_mut()
            .for_each(|item| make_paths_source_relative(item, parent)),
        _ => {}
    }
}

fn components(path: &Path) -> Vec<Component<'_>> {
    path.components()
        .filter(|part| *part != Component::CurDir)
        .collect()
}

fn same_value(expected: &FieldValue, actual: &FieldValue) -> bool {
    match (expected, actual) {
        (FieldValue::Path(a), FieldValue::Path(b)) => components(a) == components(b),
        // Firm source generation persists timestamps at minute precision.
        (FieldValue::DateTime(a), FieldValue::DateTime(b)) => {
            a.with_second(0)
                .and_then(|time| time.with_nanosecond(0))
                .as_ref()
                == Some(b)
        }
        (FieldValue::List(a), FieldValue::List(b)) => {
            a.len() == b.len() && a.iter().zip(b).all(|(a, b)| same_value(a, b))
        }
        _ => expected == actual,
    }
}
