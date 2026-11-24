use super::{CatalogModelEntry, ModelCatalog};
use serde::Deserialize;
use std::collections::HashSet;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Manifest {
    schema_version: u32,
    model_files: Vec<String>,
    preference_ranking: Vec<String>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Records {
    models: Vec<CatalogModelEntry>,
}

pub(super) fn parse(manifest: &str, resources: &[(&str, &str)]) -> Result<ModelCatalog, String> {
    let manifest: Manifest =
        toml::from_str(manifest).map_err(|e| format!("catalog manifest: {e}"))?;
    if manifest.schema_version != 1 {
        return Err("unsupported catalog schema version".into());
    }
    let mut files = HashSet::new();
    let mut patterns = HashSet::new();
    let mut entries = Vec::new();
    for file in manifest.model_files {
        if !files.insert(file.clone()) {
            return Err(format!("repeated model file: {file}"));
        }
        let text = resources
            .iter()
            .find(|(name, _)| *name == file)
            .ok_or_else(|| format!("missing model file: {file}"))?
            .1;
        let records: Records = toml::from_str(text).map_err(|e| format!("{file}: {e}"))?;
        for entry in records.models {
            if entry.pattern.is_empty() || !patterns.insert(entry.pattern.clone()) {
                return Err(format!("empty or duplicate pattern: {}", entry.pattern));
            }
            if entry.aliases.iter().any(String::is_empty)
                || entry.context_window <= 0
                || entry.max_output.is_some_and(|v| v <= 0)
                || [entry.input_cost_per_million, entry.output_cost_per_million]
                    .into_iter()
                    .flatten()
                    .any(|v| !v.is_finite() || v < 0.0)
            {
                return Err(format!("invalid metadata: {}", entry.pattern));
            }
            if let Some(control) = &entry.reasoning_control
                && [
                    Some(control.fast_effort),
                    Some(control.escalated_effort),
                    control.default_effort,
                ]
                .into_iter()
                .flatten()
                .any(|e| !control.supported_efforts.contains(&e))
            {
                return Err(format!(
                    "unsupported reasoning control effort: {}",
                    entry.pattern
                ));
            }
            entries.push(entry);
        }
    }
    if manifest.preference_ranking.iter().any(String::is_empty) {
        return Err("empty preference pattern".into());
    }
    Ok(ModelCatalog::from_parts(
        entries,
        manifest.preference_ranking,
    ))
}

pub(super) fn embedded() -> ModelCatalog {
    parse(
        include_str!("data/catalog.toml"),
        &[
            ("alibaba.toml", include_str!("data/alibaba.toml")),
            ("anthropic.toml", include_str!("data/anthropic.toml")),
            ("corti.toml", include_str!("data/corti.toml")),
            ("deepseek.toml", include_str!("data/deepseek.toml")),
            ("gemma.toml", include_str!("data/gemma.toml")),
            ("google.toml", include_str!("data/google.toml")),
            ("grok.toml", include_str!("data/grok.toml")),
            ("minimax.toml", include_str!("data/minimax.toml")),
            ("mistral.toml", include_str!("data/mistral.toml")),
            ("moonshot.toml", include_str!("data/moonshot.toml")),
            ("nvidia.toml", include_str!("data/nvidia.toml")),
            ("openai.toml", include_str!("data/openai.toml")),
            ("zhipu.toml", include_str!("data/zhipu.toml")),
        ],
    )
    .expect("embedded model catalog must be valid")
}
