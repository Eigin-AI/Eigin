//! Search endpoint handler.

use std::sync::Arc;

use axum::extract::{ConnectInfo, Query, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde::Deserialize;

use crate::AppState;
use crate::error::AppError;

/// Query parameters for the search endpoint.
#[derive(Deserialize)]
pub struct SearchParams {
    /// The search query string.
    q: Option<String>,
}

/// Handles search requests.
///
/// Validates the query, checks rate limits and quota, then proxies
/// the request to the upstream search API.
pub async fn handle(
    State(state): State<Arc<AppState>>,
    ConnectInfo(addr): ConnectInfo<std::net::SocketAddr>,
    Query(params): Query<SearchParams>,
) -> Result<Response, AppError> {
    let query = params
        .q
        .filter(|q| !q.trim().is_empty())
        .ok_or_else(|| AppError::BadRequest("missing 'q' parameter".into()))?;

    let ip = addr.ip();

    state.rate_limiter.check(ip)?;
    state.pool.try_consume()?;

    let body = state
        .search_client
        .search(&state.mojeek_api_key, &query)
        .await?;

    Ok((
        StatusCode::OK,
        [(axum::http::header::CONTENT_TYPE, "application/json")],
        body,
    )
        .into_response())
}
