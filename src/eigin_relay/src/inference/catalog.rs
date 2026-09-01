//! Model catalog: loads models.toml and serves GET /v1/models.
//! Provider catalog: loads providers.toml for upstream provider definitions.
//! Product catalog: loads products.toml for IAP credit tier mapping.

use std::collections::HashMap;
use std::sync::Arc;

use axum::Json;
use axum::extract::State;
use axum::response::IntoResponse;
use serde::{Deserialize, Serialize};

use crate::AppState;
use crate::error::AppError;

// ── Provider config ─────────────────────────────────────────────────────────

/// A single upstream provider entry in providers.toml.
#[derive(Debug, Clone, Deserialize)]
pub struct ProviderConfig {
    pub id: String,
    pub base_url: String,
}

/// The full providers.toml structure.
#[derive(Debug, Deserialize)]
pub struct ProvidersConfig {
    pub providers: Vec<ProviderConfig>,
}

impl ProvidersConfig {
    pub fn load(path: &str) -> Result<Self, String> {
        let content =
            std::fs::read_to_string(path).map_err(|e| format!("failed to read {path}: {e}"))?;
        toml::from_str(&content).map_err(|e| format!("failed to parse {path}: {e}"))
    }

    /// Build a lookup map from provider ID to config.
    pub fn into_map(self) -> HashMap<String, ProviderConfig> {
        self.providers
            .into_iter()
            .map(|p| (p.id.clone(), p))
            .collect()
    }
}

// ── Model config ─────────────────────────────────────────────────────────────

/// A single model entry in models.toml.
///
/// `id` is the canonical client-facing model ID. `upstream_id` is the ID sent
/// to the provider; if absent, `id` is used. `aliases` are additional IDs the
/// relay will accept in request bodies, mapping silently back to the canonical
/// `id`. Aliases never appear in GET /v1/models.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ModelConfig {
    pub id: String,
    pub provider: String,
    pub upstream_id: Option<String>,
    #[serde(default)]
    pub aliases: Vec<String>,
    pub input_millicredits_per_1m_tokens: u64,
    pub cached_input_millicredits_per_1m_tokens: u64,
    pub output_millicredits_per_1m_tokens: u64,
}

impl ModelConfig {
    /// The model ID to send to the upstream provider.
    pub fn upstream_id(&self) -> &str {
        self.upstream_id.as_deref().unwrap_or(&self.id)
    }
}

/// The full models.toml structure.
#[derive(Debug, Deserialize)]
pub struct ModelsConfig {
    pub models: Vec<ModelConfig>,
}

/// Resolved catalog built from models.toml with alias mapping.
pub struct ResolvedCatalog {
    /// Canonical ID → model config (used for model list + rate lookup).
    pub canonical_models: HashMap<String, ModelConfig>,
    /// All IDs (canonical + aliases) → canonical ID (used for request resolution).
    pub alias_map: HashMap<String, String>,
}

impl ModelsConfig {
    pub fn load(path: &str) -> Result<Self, String> {
        let content =
            std::fs::read_to_string(path).map_err(|e| format!("failed to read {path}: {e}"))?;
        toml::from_str(&content).map_err(|e| format!("failed to parse {path}: {e}"))
    }

    /// Build the resolved catalog: canonical models + alias map.
    ///
    /// Returns an error if a canonical ID duplicates another entry, or if an
    /// alias collides with a different entry's canonical ID.
    pub fn into_resolved(self) -> Result<ResolvedCatalog, String> {
        let mut canonical_models = HashMap::with_capacity(self.models.len());
        let mut alias_map = HashMap::new();

        for model in self.models {
            let canonical = model.id.clone();

            // Canonical IDs must be unique.
            if canonical_models.contains_key(&canonical) {
                return Err(format!("duplicate canonical model id: {canonical}"));
            }
            canonical_models.insert(canonical.clone(), model.clone());

            // Canonical ID always resolves to itself.
            alias_map.insert(canonical.clone(), canonical.clone());

            // Register aliases.
            for alias in &model.aliases {
                let alias = alias.clone();
                if let Some(existing) = alias_map.get(&alias) {
                    return Err(format!(
                        "alias '{}' for model '{}' collides with canonical id or alias of '{}'",
                        alias, canonical, existing
                    ));
                }
                alias_map.insert(alias, canonical.clone());
            }
        }

        Ok(ResolvedCatalog {
            canonical_models,
            alias_map,
        })
    }
}

/// The full products.toml structure.
///
/// Maps IAP product IDs (store-agnostic) to millicredits granted on redemption.
#[derive(Debug, Deserialize)]
pub struct ProductsConfig {
    pub products: HashMap<String, u64>,
}

impl ProductsConfig {
    pub fn load(path: &str) -> Result<Self, String> {
        let content =
            std::fs::read_to_string(path).map_err(|e| format!("failed to read {path}: {e}"))?;
        toml::from_str(&content).map_err(|e| format!("failed to parse {path}: {e}"))
    }
}

/// OpenAI-compatible model list response.
#[derive(Serialize)]
pub struct ModelsListResponse {
    pub object: &'static str,
    pub data: Vec<ModelEntry>,
}

#[derive(Serialize)]
pub struct ModelEntry {
    pub id: String,
    pub object: &'static str,
    pub owned_by: &'static str,
}

pub async fn handle_list(
    State(state): State<Arc<AppState>>,
) -> Result<impl IntoResponse, AppError> {
    let mut data: Vec<ModelEntry> = state
        .canonical_models
        .keys()
        .map(|id| ModelEntry {
            id: id.clone(),
            object: "model",
            owned_by: "eigin",
        })
        .collect();
    data.sort_unstable_by(|a, b| a.id.cmp(&b.id));

    Ok(Json(ModelsListResponse {
        object: "list",
        data,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The checked-in models.toml must load, resolve without ID/alias
    /// collisions, and reference only providers defined in providers.toml.
    /// Startup only logs a warning on a broken catalog, so this is the guard.
    #[test]
    fn checked_in_catalog_resolves_and_references_configured_providers() {
        let models_path = concat!(env!("CARGO_MANIFEST_DIR"), "/config/models.toml");
        let providers_path = concat!(env!("CARGO_MANIFEST_DIR"), "/config/providers.toml");

        let models = ModelsConfig::load(models_path)
            .unwrap_or_else(|e| panic!("failed to load {models_path}: {e}"));
        let resolved = models
            .into_resolved()
            .unwrap_or_else(|e| panic!("checked-in models.toml does not resolve: {e}"));
        let providers = ProvidersConfig::load(providers_path)
            .unwrap_or_else(|e| panic!("failed to load {providers_path}: {e}"))
            .into_map();

        assert!(!resolved.canonical_models.is_empty());
        for model in resolved.canonical_models.values() {
            assert!(
                providers.contains_key(&model.provider),
                "model '{}' references undefined provider '{}'",
                model.id,
                model.provider
            );
        }
    }
}
