//! POST /v1/chat/completions — the core inference proxy handler.
//!
//! Flow:
//! 1. Validate bearer token and wallet status + balance (admit floor check).
//! 2. Per-token + per-IP rate limiting.
//! 3. Parse body minimally: extract `model` (must be in catalog) and `stream` flag.
//!    If streaming, inject `stream_options: {include_usage: true}`.
//!    Never log the body content.
//! 4. Forward to upstream; stream bytes straight through for SSE, buffer for JSON.
//! 5. While relaying, scan SSE lines for the usage block.
//! 6. After stream completes, debit based on actual usage (or fallback).

use std::net::SocketAddr;
use std::sync::Arc;

use axum::body::Body;
use axum::extract::{ConnectInfo, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use bytes::Bytes;
use futures::StreamExt;
use serde_json::Value;

use crate::AppState;
use crate::auth::WalletBearer;
use crate::credits::{CreditLedger, Wallet, WalletStatus};
use crate::error::AppError;
use crate::inference::catalog::ModelConfig;
use crate::inference::estimate;
use crate::inference::upstream::{BoxStream, UpstreamResponse};
use crate::inference::usage::{self, UsageBlock};

/// Number of SSE chunks buffered between the upstream reader and the response body.
/// Applies backpressure to the upstream reader if the client is slow to consume.
const STREAM_CHANNEL_BUFFER: usize = 64;

pub async fn handle(
    State(state): State<Arc<AppState>>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    WalletBearer(wallet): WalletBearer,
    body: Bytes,
) -> Result<Response, AppError> {
    // Admit check and rate limiting.
    admit(&state, &wallet, addr)?;

    // Parse body to extract `model` and `stream`. Don't log the prompts.
    let (model_config, forwarded_body, estimated_usage) = prepare_body(body, &state)?;

    let upstream_key = state
        .upstream_api_key
        .as_deref()
        .ok_or_else(|| AppError::ServiceUnavailable("inference not configured".into()))?;

    // Forward to upstream.
    let upstream_response = state
        .upstream_client
        .chat_completions(forwarded_body, upstream_key)
        .await?;

    match upstream_response {
        UpstreamResponse::Stream(stream) => {
            relay_stream(stream, &state, wallet, model_config, estimated_usage)
        }
        UpstreamResponse::Buffer(bytes) => {
            relay_buffer(bytes, &state, wallet, &model_config, estimated_usage).await
        }
    }
}

/// Check that the wallet is active and above the admit floor, then apply rate limits.
fn admit(state: &AppState, wallet: &Wallet, addr: SocketAddr) -> Result<(), AppError> {
    if wallet.status != WalletStatus::Active
        || wallet.balance_millicredits < state.admit_floor_millicredits
    {
        return Err(AppError::InsufficientCredits);
    }
    state.token_rate_limiter.check(wallet.id)?;
    state.ip_rate_limiter.check(addr.ip())?;
    Ok(())
}

/// Parse the request body, look up the model, and inject `stream_options` if streaming.
/// Returns the model config, the re-serialized body to forward upstream, and a usage
/// estimate derived from message lengths (used as fallback if upstream returns no usage).
fn prepare_body(
    body: Bytes,
    state: &AppState,
) -> Result<(ModelConfig, Bytes, Option<UsageBlock>), AppError> {
    let mut json: Value = serde_json::from_slice(&body)
        .map_err(|_| AppError::BadRequest("invalid JSON body".into()))?;

    let model_id = json
        .get("model")
        .and_then(|v| v.as_str())
        .ok_or_else(|| AppError::BadRequest("missing 'model' field".into()))?
        .to_owned();

    let model_config = state
        .model_rates
        .get(&model_id)
        .cloned()
        .ok_or_else(|| AppError::BadRequest(format!("unknown model: {model_id}")))?;

    let is_stream = json
        .get("stream")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    // Inject stream_options so the upstream emits a final usage chunk.
    if is_stream {
        json["stream_options"] = serde_json::json!({ "include_usage": true });
    }

    let estimated_usage = estimate::estimate_usage(&json);

    let forwarded_body = Bytes::from(
        serde_json::to_vec(&json)
            .map_err(|e| AppError::Internal(format!("body re-serialization: {e}")))?,
    );

    Ok((model_config, forwarded_body, estimated_usage))
}

/// Relay an SSE stream to the client, scanning for usage chunks as they pass through.
/// Spawns a task that relays chunks and debits the ledger when the stream completes.
fn relay_stream(
    mut stream: BoxStream,
    state: &AppState,
    wallet: Wallet,
    model_config: ModelConfig,
    estimated_usage: Option<UsageBlock>,
) -> Result<Response, AppError> {
    let wallet_id = wallet.id;
    let ledger = Arc::clone(&state.ledger);

    let (tx, rx) = tokio::sync::mpsc::channel::<Result<Bytes, AppError>>(STREAM_CHANNEL_BUFFER);

    tokio::spawn(async move {
        let mut found_usage: Option<UsageBlock> = None;

        while let Some(chunk) = stream.next().await {
            match chunk {
                Ok(bytes) => {
                    // Scan SSE lines for usage — never log content.
                    if let Ok(text) = std::str::from_utf8(&bytes) {
                        for line in text.lines() {
                            if let Some(u) = usage::extract_from_sse_line(line) {
                                found_usage = Some(u);
                            }
                        }
                    }
                    let _ = tx.send(Ok(bytes)).await;
                }
                Err(e) => {
                    let _ = tx.send(Err(e)).await;
                    break;
                }
            }
        }

        // Debit after stream completes.
        settle(
            ledger,
            wallet_id,
            found_usage,
            estimated_usage,
            &model_config,
        )
        .await;
    });

    let stream = tokio_stream::wrappers::ReceiverStream::new(rx);
    let body = Body::from_stream(stream);

    let mut headers = HeaderMap::new();
    headers.insert("content-type", "text/event-stream".parse().unwrap());
    headers.insert("cache-control", "no-cache".parse().unwrap());
    headers.insert("x-accel-buffering", "no".parse().unwrap());

    Ok((StatusCode::OK, headers, body).into_response())
}

/// Relay a buffered JSON response to the client and debit synchronously.
async fn relay_buffer(
    bytes: Bytes,
    state: &AppState,
    wallet: Wallet,
    model_config: &ModelConfig,
    estimated_usage: Option<UsageBlock>,
) -> Result<Response, AppError> {
    let found_usage = usage::extract_from_response_body(&bytes);
    settle(
        Arc::clone(&state.ledger),
        wallet.id,
        found_usage,
        estimated_usage,
        model_config,
    )
    .await;

    Ok((
        StatusCode::OK,
        [(axum::http::header::CONTENT_TYPE, "application/json")],
        bytes,
    )
        .into_response())
}

/// Compute cost from usage and debit the ledger. Logs warnings/errors but never panics.
///
/// Priority: actual upstream usage > estimated usage from request size > no charge.
/// If neither is available the request had no estimable content — we skip the debit.
async fn settle(
    ledger: Arc<dyn CreditLedger>,
    wallet_id: uuid::Uuid,
    actual_usage: Option<UsageBlock>,
    estimated_usage: Option<UsageBlock>,
    model: &ModelConfig,
) {
    let millicredits = match actual_usage.or(estimated_usage) {
        Some(u) => crate::inference::rates::compute_cost(&u, model),
        None => {
            tracing::warn!(
                model = %model.id,
                "no usage data and request was not estimable; skipping debit"
            );
            return;
        }
    };

    if let Err(e) = ledger.debit(wallet_id, millicredits).await {
        // An accepted small-loss risk: the user got their response but we couldn't debit.
        tracing::error!(wallet_id = %wallet_id, error = %e, millicredits, "debit failed after inference");
    }
}
