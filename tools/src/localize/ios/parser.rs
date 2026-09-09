use super::format_params::count_format_parameters;
use super::identifiers::is_valid_swift_identifier;
use anyhow::{Context, Result};
use std::fs;

pub struct CatalogEntry {
    pub key: String,
    pub comment: Option<String>,
    pub param_count: usize,
}

/// A catalog key skipped by the generator because it is not `domain.element`
/// shaped — typically a string Xcode auto-extracted from a `Text("…")` literal.
#[derive(Clone)]
pub struct SkippedKey {
    pub key: String,
}

/// Result of parsing the catalog: emitted entries plus keys skipped by the
/// generator because they are not `domain.element` shaped.
///
/// Skipped keys are not failures. They are surfaced as a single aggregate
/// warning by the generate command so that copy accidentally left as a
/// literal stands out, instead of one per-key `WARNING` line per generate.
pub struct ParseResult {
    pub entries: Vec<CatalogEntry>,
    pub skipped: Vec<SkippedKey>,
}

pub fn parse(path: &str) -> Result<ParseResult> {
    let content = fs::read_to_string(path).with_context(|| format!("reading {path}"))?;
    let json: serde_json::Value =
        serde_json::from_str(&content).with_context(|| format!("parsing {path}"))?;

    let strings = json["strings"]
        .as_object()
        .context("invalid catalog format: missing 'strings' object")?;

    let mut entries = Vec::new();
    let mut skipped = Vec::new();

    for (key, value) in strings {
        let segments: Vec<&str> = key.split('.').collect();

        if segments.len() < 2
            || segments.iter().any(|s| s.is_empty())
            || !is_valid_swift_identifier(segments[0])
        {
            skipped.push(SkippedKey { key: key.clone() });
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
    Ok(ParseResult { entries, skipped })
}
