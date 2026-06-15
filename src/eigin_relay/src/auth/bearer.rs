//! Bearer token extraction and wallet lookup.
//!
//! Credit-bearing routes use `Authorization: Bearer <token>` rather than the
//! shared `x-eigin-key`. This module provides an Axum extractor that validates
//! the bearer token and resolves the wallet in a single step.

use std::sync::Arc;

use axum::extract::FromRequestParts;
use axum::http::request::Parts;

use crate::AppState;
use crate::credits::Wallet;
use crate::error::AppError;

/// An Axum extractor that resolves a valid wallet from the `Authorization: Bearer` header.
///
/// Fails with 401 if the header is missing, malformed, or the token is unknown.
pub struct WalletBearer(pub Wallet);

impl FromRequestParts<Arc<AppState>> for WalletBearer {
    type Rejection = AppError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &Arc<AppState>,
    ) -> Result<Self, Self::Rejection> {
        let token = extract_bearer_token(parts)?;
        let token_hash = crate::credits::token::hash(&token);

        let wallet = state
            .ledger
            .find_by_token_hash(&token_hash)
            .await
            .map_err(|e| AppError::Internal(format!("ledger error: {e}")))?
            .ok_or(AppError::Unauthorized)?;

        Ok(WalletBearer(wallet))
    }
}

/// Extract the raw bearer token string from request headers.
pub fn extract_bearer_token(parts: &Parts) -> Result<String, AppError> {
    let header = parts
        .headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .ok_or(AppError::Unauthorized)?;

    let token = header
        .strip_prefix("Bearer ")
        .ok_or(AppError::Unauthorized)?;

    if token.is_empty() {
        return Err(AppError::Unauthorized);
    }

    Ok(token.to_owned())
}
