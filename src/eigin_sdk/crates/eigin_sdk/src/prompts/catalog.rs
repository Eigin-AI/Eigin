use std::collections::{BTreeMap, HashMap};
use std::sync::{Arc, LazyLock};

use super::{
    config,
    template::{Templates, parser::Segment},
};

/// A catalog loading, rendering, or integration validation failure.
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum PromptCatalogError {
    /// The catalog document or template graph is invalid.
    #[error("Invalid prompt catalog: {message}")]
    InvalidCatalog { message: String },
    /// The requested template does not exist.
    #[error("Unknown prompt template: {name}")]
    UnknownTemplate { name: String },
    /// Supplied parameters do not match the template's requirements.
    #[error("Invalid parameters for {name}: {message}")]
    InvalidParameters { name: String, message: String },
    /// Declared host usages do not match the catalog.
    #[error("Prompt usage mismatches: {message}")]
    InvalidUsages { message: String },
}

/// An immutable, validated catalog. Loading and rendering require no host services.
#[derive(Debug, uniffi::Object)]
pub struct PromptCatalog {
    pub(super) templates: Templates,
    pub(super) parameters: BTreeMap<String, Vec<String>>,
}

#[uniffi::export]
impl PromptCatalog {
    /// Returns the shared embedded Eigin catalog without SDK initialization.
    #[uniffi::constructor]
    pub fn default_catalog() -> Arc<Self> {
        static DEFAULT: LazyLock<Arc<PromptCatalog>> = LazyLock::new(|| {
            PromptCatalog::from_json(include_str!("../../resources/prompts.json").to_owned())
                .expect("embedded prompt catalog must be valid")
        });
        DEFAULT.clone()
    }

    /// Loads a complete independent catalog; never merges with the default.
    #[uniffi::constructor]
    pub fn from_json(document: String) -> Result<Arc<Self>, PromptCatalogError> {
        config::load(&document)
            .map(Arc::new)
            .map_err(|message| PromptCatalogError::InvalidCatalog { message })
    }

    /// Renders a named template with exactly its required string parameters.
    pub fn render(
        &self,
        name: String,
        parameters: HashMap<String, String>,
    ) -> Result<String, PromptCatalogError> {
        let required = self
            .parameters
            .get(&name)
            .ok_or_else(|| PromptCatalogError::UnknownTemplate { name: name.clone() })?;
        if let Some(message) = mismatch(required, parameters.keys().cloned().collect()) {
            return Err(PromptCatalogError::InvalidParameters { name, message });
        }
        let mut output = String::new();
        self.append(&self.templates[&name], &parameters, &mut output);
        Ok(output)
    }

    /// Checks declared host usages together before conversations render prompts.
    /// Unreferenced catalog entries are allowed; parameter sets must match exactly.
    pub fn validate_usages(
        &self,
        usages: HashMap<String, Vec<String>>,
    ) -> Result<(), PromptCatalogError> {
        let mut errors = Vec::new();
        for (name, supplied) in BTreeMap::from_iter(usages) {
            match self.parameters.get(&name) {
                None => errors.push(format!("{name}: unknown template")),
                Some(required) => {
                    if let Some(message) = mismatch(required, supplied) {
                        errors.push(format!("{name}: {message}"));
                    }
                }
            }
        }
        if errors.is_empty() {
            Ok(())
        } else {
            Err(PromptCatalogError::InvalidUsages {
                message: errors.join("; "),
            })
        }
    }
}

impl PromptCatalog {
    fn append(&self, segments: &[Segment], values: &HashMap<String, String>, out: &mut String) {
        let mut pending = vec![segments.iter()];
        while let Some(frame) = pending.last_mut() {
            let Some(segment) = frame.next() else {
                pending.pop();
                continue;
            };
            match segment {
                Segment::Text(text) => out.push_str(text),
                Segment::Var(name) => out.push_str(&values[name]),
                Segment::Include(name) => pending.push(self.templates[name].iter()),
                Segment::If { cond, then, els } => {
                    pending.push(if values[cond].is_empty() {
                        els.iter()
                    } else {
                        then.iter()
                    });
                }
            }
        }
    }
}

fn mismatch(required: &[String], mut supplied: Vec<String>) -> Option<String> {
    supplied.sort();
    let duplicate = supplied.windows(2).any(|pair| pair[0] == pair[1]);
    let missing: Vec<_> = required
        .iter()
        .filter(|key| !supplied.contains(key))
        .collect();
    let extra: Vec<_> = supplied
        .iter()
        .filter(|key| !required.contains(key))
        .collect();
    if missing.is_empty() && extra.is_empty() && !duplicate {
        None
    } else {
        Some(format!(
            "missing {missing:?}, unexpected {extra:?}, duplicate names: {duplicate}"
        ))
    }
}
