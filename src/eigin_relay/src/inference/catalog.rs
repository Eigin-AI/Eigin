//! Model catalog: loads models.toml and serves GET /v1/models.
//! Product catalog: loads products.toml for IAP credit tier mapping.

use std::collections::HashMap;
use std::sync::Arc;

use axum::Json;
use axum::extract::State;
use axum::response::IntoResponse;
use serde::{Deserialize, Serialize};

use crate::AppState;
use crate::error::AppError;

/// A single model entry in models.toml.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ModelConfig {
    pub id: String,
    pub input_millicredits_per_1m_tokens: u64,
    pub cached_input_millicredits_per_1m_tokens: u64,
    pub output_millicredits_per_1m_tokens: u64,
}

/// The full models.toml structure.
#[derive(Debug, Deserialize)]
pub struct ModelsConfig {
    pub models: Vec<ModelConfig>,
}

impl ModelsConfig {
    pub fn load(path: &str) -> Result<Self, String> {
        let content =
            std::fs::read_to_string(path).map_err(|e| format!("failed to read {path}: {e}"))?;
        toml::from_str(&content).map_err(|e| format!("failed to parse {path}: {e}"))
    }

    /// Build a lookup map from model ID to rates.
    pub fn into_rate_map(self) -> HashMap<String, ModelConfig> {
        self.models.into_iter().map(|m| (m.id.clone(), m)).collect()
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
        .model_rates
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
