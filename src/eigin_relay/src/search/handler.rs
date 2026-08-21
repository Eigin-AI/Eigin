//! Search endpoint handler.

use std::sync::Arc;

use axum::extract::{Query, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde::{Deserialize, Serialize};

use super::client::SearchOptions;
use crate::AppState;
use crate::error::AppError;

/// Quota key for the shared search community pool.
const SEARCH_QUOTA_KEY: &str = "search";

/// Query parameters for the search endpoint.
#[derive(Deserialize)]
pub struct SearchParams {
    /// The search query string.
    q: Option<String>,
    /// ISO 3166-1 alpha-2 region code, used to boost regionally relevant results.
    region: Option<String>,
    /// A named site focus (e.g. "recipes"), mapped server-side to a curated domain list.
    focus: Option<String>,
}

/// A single reshaped search result.
#[derive(Serialize)]
struct SearchResultItem {
    title: String,
    url: String,
    desc: String,
}

/// The structured response returned to clients, in place of the raw Mojeek payload.
#[derive(Serialize)]
struct SearchResponse {
    results: Vec<SearchResultItem>,
}

/// The subset of Mojeek's JSON response shape needed to reshape results.
#[derive(Deserialize)]
struct MojeekResponse {
    response: MojeekResponseBody,
}

#[derive(Deserialize)]
struct MojeekResponseBody {
    #[serde(default)]
    results: Vec<MojeekResult>,
}

#[derive(Deserialize)]
struct MojeekResult {
    title: String,
    url: String,
    #[serde(default)]
    desc: String,
}

/// Handles search requests.
///
/// Validates the query and checks the shared search quota, then proxies the
/// request to the upstream search API and reshapes the response into a
/// small, stable shape rather than passing Mojeek's raw payload through.
/// Per-IP rate limiting is applied by the router layer, not here.
pub async fn handle(
    State(state): State<Arc<AppState>>,
    Query(params): Query<SearchParams>,
) -> Result<Response, AppError> {
    let query = params
        .q
        .filter(|q| !q.trim().is_empty())
        .ok_or_else(|| AppError::BadRequest("missing 'q' parameter".into()))?;

    let options = SearchOptions::parse(params.region.as_deref(), params.focus.as_deref());

    match state
        .quota
        .try_consume(
            SEARCH_QUOTA_KEY,
            1,
            state.search_pool_max,
            state.search_window,
        )
        .await
    {
        Ok(()) => {}
        Err(crate::quota::QuotaError::Exhausted) => return Err(AppError::PoolExhausted),
        Err(crate::quota::QuotaError::Internal(msg)) => return Err(AppError::Internal(msg)),
    }

    let body = state
        .search_client
        .search(&state.mojeek_api_key, &query, &options)
        .await?;

    let parsed: MojeekResponse = serde_json::from_slice(&body)
        .map_err(|e| AppError::Upstream(format!("invalid search response: {e}")))?;

    let reshaped = SearchResponse {
        results: parsed
            .response
            .results
            .into_iter()
            .map(|r| SearchResultItem {
                title: r.title,
                url: r.url,
                desc: r.desc,
            })
            .collect(),
    };

    let out = serde_json::to_vec(&reshaped)
        .map_err(|e| AppError::Internal(format!("failed to encode search response: {e}")))?;

    Ok((
        StatusCode::OK,
        [(axum::http::header::CONTENT_TYPE, "application/json")],
        out,
    )
        .into_response())
}
