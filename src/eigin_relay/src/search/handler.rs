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
    /// Legacy client parameter. Staan has no region boost, so it is accepted
    /// but not forwarded upstream.
    region: Option<String>,
    /// A named site focus (e.g. "recipes"), mapped server-side to a curated domain list.
    focus: Option<String>,
}

/// The structured response returned to clients.
#[derive(Serialize)]
struct SearchResponse {
    results: Vec<super::client::SearchResultItem>,
}

/// Handles search requests.
///
/// Validates the query and checks the shared search quota, then proxies the
/// request to the upstream search API. The client reshapes the provider's raw
/// payload, so this handler only serializes the small, stable result shape.
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

    let results = state
        .search_client
        .search(&state.staan_api_key, &query, &options)
        .await?;

    let out = serde_json::to_vec(&SearchResponse { results })
        .map_err(|e| AppError::Internal(format!("failed to encode search response: {e}")))?;

    Ok((
        StatusCode::OK,
        [(axum::http::header::CONTENT_TYPE, "application/json")],
        out,
    )
        .into_response())
}
