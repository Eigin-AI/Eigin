//! POST /credits/redeem — entitlement redemption and restore handler.
//!
//! Flow:
//! 1. Verify the entitlement proof (dispatched by `type`: `apple_iap` or `grant`).
//! 2. Map the product ID to a credit amount via `config/products.toml`.
//! 3. Fingerprint = SHA-256 of the source's stable id (Apple's originalTransactionId,
//!    or `iss:jti` for a grant), scoped by origin.
//! 4. If no wallet exists: generate a new token, mint, return.
//!    If a wallet exists: decrypt and return the same stable token.
//!
//! Calling redeem with the same entitlement always returns the same
//! token and the current (spent-down) balance. Credits are never re-minted.
//! New store types slot in by adding a `type` variant and a verifier — the
//! wallet and token machinery is origin-agnostic.

use std::sync::Arc;

use axum::Json;
use axum::extract::State;
use axum::response::IntoResponse;
use serde::{Deserialize, Serialize};

use crate::AppState;
use crate::credits::apple::AppleEnvironment;
use crate::credits::ledger::{LedgerError, WalletOrigin};
use crate::credits::token;
use crate::error::AppError;
use crate::quota::QuotaError;

/// Quota key for the Apple Sandbox credit-issuance budget.
const SANDBOX_QUOTA_KEY: &str = "apple_sandbox_credits";

#[derive(Deserialize)]
pub struct RedeemRequest {
    /// Entitlement source discriminator. Determines how `proof` is interpreted.
    pub r#type: String,
    /// Credential issued by the entitlement source.
    /// For `apple_iap`: a StoreKit 2 `Transaction.jwsRepresentation`.
    /// For `grant`: an Ed25519-signed grant JWT.
    pub proof: String,
}

#[derive(Serialize)]
pub struct RedeemResponse {
    /// The opaque bearer token to use for inference and balance checks.
    pub token: String,
    /// Whole credits remaining in this wallet.
    pub credits: i64,
    /// Wallet status: "active", "refunded", or "closed".
    pub status: String,
}

/// Mint a new wallet or restore an existing one for the given (origin, fingerprint) pair.
///
/// Tries to mint optimistically. If the fingerprint already exists (concurrent or repeated
/// redeem), falls back to looking up and decrypting the existing stable token.
async fn mint_or_restore(
    state: &AppState,
    origin: &WalletOrigin,
    fingerprint: &str,
    product_id: &str,
    millicredits: i64,
) -> Result<(String, crate::credits::Wallet), AppError> {
    let new_token = token::generate();
    let new_hash = token::hash(&new_token.0);
    let new_ciphertext = token::encrypt(&new_token.0, &new_hash, &state.token_encryption_key)?;

    match state
        .ledger
        .mint(
            origin,
            fingerprint,
            product_id,
            millicredits,
            &new_hash,
            &new_ciphertext,
        )
        .await
    {
        Ok(wallet) => Ok((new_token.0, wallet)),
        Err(LedgerError::DuplicateFingerprint) => {
            // Already minted — look up and return the existing stable token.
            let wallet = state
                .ledger
                .find_by_fingerprint(origin, fingerprint)
                .await
                .map_err(|e| AppError::Internal(format!("ledger error: {e}")))?
                .ok_or_else(|| AppError::Internal("wallet vanished after duplicate".into()))?;

            let token = token::decrypt(
                &wallet.token_ciphertext,
                &wallet.token_hash,
                &state.token_encryption_key,
            )?;
            Ok((token, wallet))
        }
        Err(e) => Err(AppError::Internal(format!("ledger error: {e}"))),
    }
}

pub async fn handle(
    State(state): State<Arc<AppState>>,
    Json(req): Json<RedeemRequest>,
) -> Result<impl IntoResponse, AppError> {
    // 1. Dispatch on entitlement type, verify the proof, and derive the wallet's
    //    origin, fingerprint, and product. Each source supplies its own stable,
    //    unique identifier for the fingerprint so re-redeeming restores the wallet.
    let (origin, fingerprint, product_id) = match req.r#type.as_str() {
        "apple_iap" => {
            let tx = state.apple_verifier.verify_transaction(&req.proof)?;
            let origin = match tx.environment {
                AppleEnvironment::Production => WalletOrigin::AppleAppStore,
                AppleEnvironment::Sandbox => WalletOrigin::AppleAppStoreSandbox,
            };
            (
                origin,
                token::hash(&tx.original_transaction_id),
                tx.product_id,
            )
        }
        "grant" => {
            let grant = state.grant_verifier.verify(&req.proof)?;
            (
                WalletOrigin::Grant,
                token::hash(&format!("{}:{}", grant.issuer, grant.grant_id)),
                grant.product_id,
            )
        }
        other => {
            return Err(AppError::BadRequest(format!(
                "unknown entitlement type: {other}"
            )));
        }
    };

    // 2. Map productId → millicredits.
    let millicredits = state
        .product_credits
        .get(&product_id)
        .copied()
        .ok_or_else(|| AppError::BadRequest(format!("unknown productId: {product_id}")))?;

    // 3. Check quota for Apple Sandbox purchases.
    if origin == WalletOrigin::AppleAppStoreSandbox
        && state
            .ledger
            .find_by_fingerprint(&origin, &fingerprint)
            .await
            .map_err(|e| AppError::Internal(format!("ledger error: {e}")))?
            .is_none()
    {
        let credits = (millicredits / 1000).max(0) as u64;
        match state
            .quota
            .try_consume(
                SANDBOX_QUOTA_KEY,
                credits,
                state.sandbox_budget_credits,
                state.sandbox_budget_window,
            )
            .await
        {
            Ok(()) => {}
            Err(QuotaError::Exhausted) => return Err(AppError::SandboxBudgetExhausted),
            Err(QuotaError::Internal(msg)) => return Err(AppError::Internal(msg)),
        }
    }

    // 4. Mint or restore.
    let (resolved_token, wallet) =
        mint_or_restore(&state, &origin, &fingerprint, &product_id, millicredits).await?;

    Ok(Json(RedeemResponse {
        token: resolved_token,
        credits: wallet.credits(),
        status: wallet.status.as_str().to_owned(),
    }))
}
