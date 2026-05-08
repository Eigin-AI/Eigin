use super::format_params::count_format_parameters;
use super::identifiers::is_valid_swift_identifier;
use anyhow::{Context, Result};
use std::fs;

pub struct CatalogEntry {
    pub key: String,
    pub comment: Option<String>,
    pub param_count: usize,
}

pub fn parse(path: &str) -> Result<Vec<CatalogEntry>> {
    let content = fs::read_to_string(path).with_context(|| format!("reading {path}"))?;
    let json: serde_json::Value =
        serde_json::from_str(&content).with_context(|| format!("parsing {path}"))?;

    let strings = json["strings"]
        .as_object()
        .context("invalid catalog format: missing 'strings' object")?;

    let mut entries = Vec::new();

    for (key, value) in strings {
        let segments: Vec<&str> = key.split('.').collect();

        if segments.len() < 2 {
            eprintln!("WARNING: Skipping key '{key}' — must have at least domain.element");
            continue;
        }
        if segments.iter().any(|s| s.is_empty()) {
            eprintln!("WARNING: Skipping key '{key}' — empty segment detected");
            continue;
        }
        if !is_valid_swift_identifier(segments[0]) {
            eprintln!(
                "WARNING: Skipping key '{key}' — domain '{}' is not a valid Swift identifier",
                segments[0]
            );
            continue;
        }

        let comment = value["comment"].as_str().map(String::from);
        let en_value = value["localizations"]["en"]["stringUnit"]["value"]
            .as_str()
            .map(String::from);
        let param_count = en_value
            .as_deref()
            .map(count_format_parameters)
            .unwrap_or(0);

        entries.push(CatalogEntry {
            key: key.clone(),
            comment,
            param_count,
        });
    }

    entries.sort_by(|a, b| a.key.cmp(&b.key));
    Ok(entries)
}
