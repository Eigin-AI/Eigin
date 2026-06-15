//! GET /credits/balance — return the current balance for a credit token.

use axum::Json;
use axum::response::IntoResponse;
use serde::Serialize;

use crate::auth::WalletBearer;
use crate::error::AppError;

#[derive(Serialize)]
pub struct BalanceResponse {
    /// Whole credits remaining (floor division of millicredits).
    pub credits: i64,
    /// Wallet status: "active", "refunded", or "closed".
    pub status: String,
}

pub async fn handle(WalletBearer(wallet): WalletBearer) -> Result<impl IntoResponse, AppError> {
    Ok(Json(BalanceResponse {
        credits: wallet.credits(),
        status: wallet.status.as_str().to_owned(),
    }))
}
