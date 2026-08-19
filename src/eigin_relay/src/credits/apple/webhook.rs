//! POST /webhooks/apple/appstore — App Store Server Notifications V2 handler.
//!
//! Apple sends a signed JSON payload when a refund or other event occurs.
//! We:
//! 1. Check the per-IP rate limit (this route is unauthenticated by design,
//!    so nothing costlier runs ahead of it — not even JSON parsing).
//! 2. Parse the body and verify the signature.
//! 3. Check `signedDate` is within a freshness window (replay defense-in-depth).
//! 4. Deduplicate on notificationUUID (idempotency).
//! 5. On REFUND: find the wallet by (origin, fingerprint) and close it.
//! 6. Always respond 200 promptly — Apple retries on non-2xx.
//!
//! Note: REVOKE (family sharing revocation) is not currently handled — it maps
//! to `NotificationType::Other` and is logged but takes no credit action.

use std::net::SocketAddr;
use std::sync::Arc;

use axum::extract::{ConnectInfo, State};
use axum::http::StatusCode;
use axum::response::IntoResponse;
use bytes::Bytes;
use serde::Deserialize;
use time::OffsetDateTime;

use super::{AppleEnvironment, NotificationType, VerifiedNotification};
use crate::AppState;
use crate::credits::ledger::{WalletOrigin, WalletStatus};
use crate::credits::token;
use crate::error::AppError;

/// Widest gap between Apple's original notification attempt and its last
/// retry: 5 retries at 1/12/24/48/72h after the previous attempt (~157h),
/// plus margin. Notifications signed outside this window are rejected.
const FRESHNESS_WINDOW: time::Duration = time::Duration::days(7);

/// Tolerance for clock skew between Apple and this server. A `signedDate`
/// further in the future than this is rejected rather than accepted.
const FUTURE_SKEW_TOLERANCE: time::Duration = time::Duration::minutes(5);

#[derive(Deserialize)]
pub struct WebhookRequest {
    #[serde(rename = "signedPayload")]
    pub signed_payload: String,
}

pub async fn handle(
    State(state): State<Arc<AppState>>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    body: Bytes,
) -> Result<impl IntoResponse, AppError> {
    // Bound parse and verification work before either runs — this route is
    // unauthenticated by design (Apple cannot present a credential). Taking
    // the body as raw bytes (rather than a `Json` extractor) keeps `serde_json`
    // parsing behind this check, matching the inference handler's admit-then-parse
    // order.
    state.webhook_rate_limiter.check(addr.ip())?;

    let req: WebhookRequest = match serde_json::from_slice(&body) {
        Ok(req) => req,
        Err(e) => {
            // Malformed body — log and return 200 so Apple doesn't retry a payload
            // that will never parse.
            tracing::warn!(error = %e, "apple webhook body failed to parse");
            return Ok(StatusCode::OK.into_response());
        }
    };

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

    if !is_fresh(&notification) {
        tracing::warn!(
            uuid = %notification.notification_uuid,
            signed_date = ?notification.signed_date,
            "stale or missing signedDate, rejecting notification"
        );
        return Ok(StatusCode::OK.into_response());
    }

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

/// Whether `signed_date` falls within the freshness window: not missing, not
/// older than `FRESHNESS_WINDOW`, and not further ahead than
/// `FUTURE_SKEW_TOLERANCE`. `signedDate` sits inside the signed payload, so a
/// forged value would invalidate the signature — this only bounds replay of a
/// genuinely old (or clock-skewed) notification.
fn is_fresh(notification: &VerifiedNotification) -> bool {
    let Some(signed_date) = notification.signed_date else {
        return false;
    };
    let now = OffsetDateTime::now_utc();
    let age = now - signed_date;
    age <= FRESHNESS_WINDOW && age >= -FUTURE_SKEW_TOLERANCE
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
