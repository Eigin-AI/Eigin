//! Health check endpoint.

use axum::http::StatusCode;
use axum::response::IntoResponse;
use serde_json::json;

/// Health check response.
#[derive(serde::Serialize)]
pub struct HealthResponse {
    pub status: &'static str,
}

/// Handles health check requests.
///
/// Returns a JSON response indicating the service is running.
pub async fn handler() -> impl IntoResponse {
    let response = HealthResponse { status: "ok" };
    (StatusCode::OK, axum::Json(json!(response)))
}
