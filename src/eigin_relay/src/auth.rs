//! Authentication middleware for the relay.

use std::sync::Arc;

use axum::extract::{Request, State};
use axum::middleware::Next;
use axum::response::Response;

use crate::AppState;
use crate::error::AppError;

/// Header name for passing the relay authentication key.
const EIGIN_KEY_HEADER: &str = "x-eigin-key";

/// Middleware that validates the `x-eigin-key` header.
///
/// Checks that the request includes a valid relay key matching `AppState.eigin_relay_key`.
/// Returns `AppError::Unauthorized` if the key is missing or incorrect.
pub async fn require_eigin_key(
    State(state): State<Arc<AppState>>,
    request: Request,
    next: Next,
) -> Result<Response, AppError> {
    let provided = request
        .headers()
        .get(EIGIN_KEY_HEADER)
        .and_then(|v| v.to_str().ok());

    match provided {
        Some(key) if key == state.eigin_relay_key => Ok(next.run(request).await),
        _ => Err(AppError::Unauthorized),
    }
}
