//! POST /webhooks/apple/appstore — App Store Server Notifications V2 handler.
//!
//! Apple sends a signed JSON payload when a refund or other event occurs.
//! We:
//! 1. Verify the signature.
//! 2. Deduplicate on notificationUUID (idempotency).
//! 3. On REFUND: find the wallet by (origin, fingerprint) and close it.
//! 4. Always respond 200 promptly — Apple retries on non-2xx.
//!
//! Note: REVOKE (family sharing revocation) is not currently handled — it maps
//! to `NotificationType::Other` and is logged but takes no credit action.

use std::sync::Arc;

use axum::Json;
use axum::extract::State;
use axum::http::StatusCode;
use axum::response::IntoResponse;
use serde::Deserialize;

use super::{AppleEnvironment, NotificationType};
use crate::AppState;
use crate::credits::ledger::{WalletOrigin, WalletStatus};
use crate::credits::token;
use crate::error::AppError;

#[derive(Deserialize)]
pub struct WebhookRequest {
    #[serde(rename = "signedPayload")]
    pub signed_payload: String,
}

pub async fn handle(
    State(state): State<Arc<AppState>>,
    Json(req): Json<WebhookRequest>,
) -> Result<impl IntoResponse, AppError> {
    // Verify the notification signature.
    let notification = match state
        .apple_verifier
        .verify_notification(&req.signed_payload)
    {
        Ok(n) => n,
        Err(e) => {
            // Invalid signature — log and return 200 to stop Apple retrying a malformed payload.
            tracing::warn!(error = %e, "apple notification verification failed");
            return Ok(StatusCode::OK.into_response());
        }
    };

    // Make sure this is a new notification we want to act on.
    let is_new = state
        .ledger
        .record_notification(&notification.notification_uuid)
        .await
        .map_err(|e| AppError::Internal(format!("ledger error: {e}")))?;

    if !is_new {
        tracing::debug!(uuid = %notification.notification_uuid, "duplicate notification, ignoring");
        return Ok(StatusCode::OK.into_response());
    }

    // Act on notification.
    match notification.notification_type {
        NotificationType::Refund => {
            close_wallet_for_refund(
                &state,
                &notification.notification_uuid,
                notification.original_transaction_id,
                notification.environment,
            )
            .await;
        }
        NotificationType::Other(ref t) => {
            tracing::debug!(notification_type = %t, "unhandled notification type");
        }
    }

    Ok(StatusCode::OK.into_response())
}

/// Look up the wallet for the refunded transaction and close it.
/// Logs errors but never fails — the caller always returns 200.
async fn close_wallet_for_refund(
    state: &AppState,
    notification_uuid: &str,
    original_transaction_id: Option<String>,
    environment: AppleEnvironment,
) {
    let Some(original_tx_id) = original_transaction_id else {
        tracing::warn!(
            uuid = %notification_uuid,
            "refund notification missing originalTransactionId"
        );
        return;
    };

    let fingerprint = token::hash(&original_tx_id);
    // Scope the lookup to the same environment the wallet was minted under, so a
    // sandbox refund closes the sandbox wallet and not a production one.
    let origin = match environment {
        AppleEnvironment::Production => WalletOrigin::AppleAppStore,
        AppleEnvironment::Sandbox => WalletOrigin::AppleAppStoreSandbox,
    };

    match state
        .ledger
        .find_by_fingerprint(&origin, &fingerprint)
        .await
    {
        Ok(Some(wallet)) => {
            if let Err(e) = state.ledger.close(wallet.id, WalletStatus::Refunded).await {
                tracing::error!(
                    wallet_id = %wallet.id,
                    error = %e,
                    "failed to close wallet on refund"
                );
            } else {
                tracing::info!(
                    wallet_id = %wallet.id,
                    notification_uuid = %notification_uuid,
                    "wallet closed due to refund"
                );
            }
        }
        Ok(None) => {
            // No wallet for this transaction — may be a test or untracked purchase.
            tracing::debug!(
                fingerprint = %fingerprint,
                "refund notification for unknown transaction"
            );
        }
        Err(e) => {
            tracing::error!(error = %e, "ledger error looking up wallet for refund");
        }
    }
}
