//! POST /v1/chat/completions — the core inference proxy handler.
//!
//! Flow:
//! 1. Validate bearer token and wallet status; per-token rate limiting (per-IP
//!    is applied by the router layer).
//! 2. Parse body minimally: extract `model` (must be in catalog) and `stream` flag.
//!    If streaming, inject `stream_options: {include_usage: true}`.
//!    Never log the body content.
//! 3. Reserve the estimated cost against the balance before forwarding — an atomic
//!    conditional debit that refuses on overdraft, so concurrent requests can't each
//!    draw the same balance.
//! 4. Forward to upstream; stream bytes straight through for SSE, buffer for JSON.
//! 5. While relaying, scan SSE lines for the usage block.
//! 6. After the stream completes, settle by applying `actual − reserved` (charge the
//!    overrun, refund the surplus). A failed forward refunds the reservation in full.

use std::sync::Arc;

use axum::body::Body;
use axum::extract::State;
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use bytes::Bytes;
use futures::StreamExt;
use serde_json::Value;

use crate::AppState;
use crate::auth::WalletBearer;
use crate::credits::{CreditLedger, LedgerError, Wallet, WalletStatus};
use crate::error::AppError;
use crate::inference::catalog::ModelConfig;
use crate::inference::estimate;
use crate::inference::rates;
use crate::inference::upstream::{BoxStream, UpstreamResponse};
use crate::inference::usage::{self, UsageBlock};

/// Number of SSE chunks buffered between the upstream reader and the response body.
/// Applies backpressure to the upstream reader if the client is slow to consume.
const STREAM_CHANNEL_BUFFER: usize = 64;

/// Nominal hold applied when a request carries no estimable content (e.g. vision
/// messages). A positive hold means an unestimable request still requires a
/// positive balance to admit, rather than being free.
const NOMINAL_HOLD_MILLICREDITS: i64 = 1;

pub async fn handle(
    State(state): State<Arc<AppState>>,
    WalletBearer(wallet): WalletBearer,
    body: Bytes,
) -> Result<Response, AppError> {
    // Wallet status + per-token rate limiting. Per-IP limiting is handled by the router layer.
    admit(&state, &wallet)?;

    // Parse body to extract `model` and `stream`. Don't log the prompts.
    let (model_config, forwarded_body, estimated_usage) = prepare_body(body, &state)?;

    // Resolve the upstream provider before reserving, so a misconfigured provider
    // fails (503) without holding credits against the balance.
    let provider_id = &model_config.provider;
    let client = state.provider_clients.get(provider_id).ok_or_else(|| {
        AppError::ServiceUnavailable(format!("provider {provider_id} not configured"))
    })?;
    let api_key = state.provider_keys.get(provider_id).ok_or_else(|| {
        AppError::ServiceUnavailable(format!("provider {provider_id} has no key"))
    })?;

    // Reserve the estimated cost before forwarding. This is the concurrency-safe
    // balance gate: concurrent requests can't each draw the same balance, because
    // each hold is an atomic conditional debit that refuses on overdraft.
    let reserved_millicredits = reservation_millicredits(estimated_usage.as_ref(), &model_config);
    reserve(&state.ledger, wallet.id, reserved_millicredits).await?;

    // Forward to upstream. A failure here sends nothing to the client, so the
    // reservation is refunded in full — we never charge for an unserved request.
    let upstream_response = match client.chat_completions(forwarded_body, api_key).await {
        Ok(resp) => resp,
        Err(e) => {
            refund_reservation(&state.ledger, wallet.id, reserved_millicredits).await;
            return Err(e);
        }
    };

    match upstream_response {
        UpstreamResponse::Stream(stream) => relay_stream(
            stream,
            &state,
            wallet,
            model_config,
            estimated_usage,
            reserved_millicredits,
        ),
        UpstreamResponse::Buffer(bytes) => {
            relay_buffer(
                bytes,
                &state,
                wallet,
                &model_config,
                estimated_usage,
                reserved_millicredits,
            )
            .await
        }
    }
}

/// Check that the wallet is active and apply the per-token rate limit. The balance
/// gate is the reservation in [`handle`], not a static floor — a wallet with any
/// positive balance is admitted as long as it can cover the estimated cost.
fn admit(state: &AppState, wallet: &Wallet) -> Result<(), AppError> {
    if wallet.status != WalletStatus::Active {
        return Err(AppError::InsufficientCredits);
    }
    state.token_rate_limiter.check(wallet.id)?;
    Ok(())
}

/// The millicredits held against the balance before serving a request. Uses the
/// request estimate when available; otherwise a nominal 1 mc so an unestimable
/// request still requires a positive balance to admit.
fn reservation_millicredits(estimated: Option<&UsageBlock>, model: &ModelConfig) -> i64 {
    match estimated {
        Some(u) => rates::compute_cost(u, model),
        None => NOMINAL_HOLD_MILLICREDITS,
    }
}

/// Reserve the estimated cost, mapping an overdraft to a 402.
async fn reserve(
    ledger: &Arc<dyn CreditLedger>,
    wallet_id: uuid::Uuid,
    millicredits: i64,
) -> Result<(), AppError> {
    ledger
        .reserve(wallet_id, millicredits)
        .await
        .map_err(|e| match e {
            LedgerError::InsufficientBalance | LedgerError::NotFound => {
                AppError::InsufficientCredits
            }
            other => AppError::Internal(format!("ledger reserve: {other}")),
        })
}

/// Parse the request body, resolve model aliases, look up the model config, and inject
/// `stream_options` if streaming. Returns the resolved model config, the re-serialized
/// body to forward upstream (with model ID rewritten to `upstream_id`), and a usage
/// estimate derived from message lengths.
///
/// Alias resolution: if the client sends an alias, it is silently mapped to the
/// canonical model before lookup. The forwarded body uses the provider's expected
/// `upstream_id`, not the canonical or alias ID.
fn prepare_body(
    body: Bytes,
    state: &AppState,
) -> Result<(ModelConfig, Bytes, Option<UsageBlock>), AppError> {
    let mut json: Value = serde_json::from_slice(&body)
        .map_err(|_| AppError::BadRequest("invalid JSON body".into()))?;

    let request_model_id = json
        .get("model")
        .and_then(|v| v.as_str())
        .ok_or_else(|| AppError::BadRequest("missing 'model' field".into()))?
        .to_owned();

    // Resolve alias -> canonical ID.
    let canonical_id = state
        .alias_map
        .get(&request_model_id)
        .cloned()
        .ok_or_else(|| AppError::BadRequest(format!("unknown model: {request_model_id}")))?;

    let model_config = state
        .canonical_models
        .get(&canonical_id)
        .cloned()
        .ok_or_else(|| AppError::Internal(format!("canonical model missing: {canonical_id}")))?;

    let is_stream = json
        .get("stream")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    // Inject stream_options so the upstream emits a final usage chunk.
    if is_stream {
        json["stream_options"] = serde_json::json!({ "include_usage": true });
    }

    // Rewrite model to upstream_id before forwarding.
    json["model"] = serde_json::Value::String(model_config.upstream_id().to_string());

    let estimated_usage = estimate::estimate_usage(&json);

    let forwarded_body = Bytes::from(
        serde_json::to_vec(&json)
            .map_err(|e| AppError::Internal(format!("body re-serialization: {e}")))?,
    );

    Ok((model_config, forwarded_body, estimated_usage))
}

/// Relay an SSE stream to the client, scanning usage chunks on the way through.
///
/// No output shipped ⇒ refund in full (the hedge-loser case). Output shipped
/// but cut before the usage chunk ⇒ charged the estimate — cancelling at the
/// end must never buy the answer for free. See the comment inside for why the
/// upstream read stops with the client.
fn relay_stream(
    mut stream: BoxStream,
    state: &AppState,
    wallet: Wallet,
    model_config: ModelConfig,
    estimated_usage: Option<UsageBlock>,
    reserved_millicredits: i64,
) -> Result<Response, AppError> {
    let wallet_id = wallet.id;
    let ledger = Arc::clone(&state.ledger);

    let (tx, rx) = tokio::sync::mpsc::channel::<Result<Bytes, AppError>>(STREAM_CHANNEL_BUFFER);

    tokio::spawn(async move {
        let mut found_usage: Option<UsageBlock> = None;
        // Whether any output token was shipped — the refund rule's input.
        let mut output_shipped = false;
        // SSE lines split across chunks; hold the trailing fragment back so
        // each line is scanned whole. Pure transport bytes — never logged.
        let mut line_buffer: Vec<u8> = Vec::new();

        fn scan_chunk(
            line_buffer: &mut Vec<u8>,
            chunk: &[u8],
            output_shipped: &mut bool,
            found_usage: &mut Option<UsageBlock>,
        ) {
            line_buffer.extend_from_slice(chunk);
            let scan_to = line_buffer
                .iter()
                .rposition(|&b| b == b'\n')
                .map_or(0, |i| i + 1);
            if let Ok(text) = std::str::from_utf8(&line_buffer[..scan_to]) {
                for line in text.lines() {
                    if let Some(u) = usage::extract_from_sse_line(line) {
                        *found_usage = Some(u);
                    }
                    if usage::carries_output(line) {
                        *output_shipped = true;
                    }
                }
            }
            line_buffer.drain(..scan_to);
        }

        while let Some(chunk) = stream.next().await {
            match chunk {
                Ok(bytes) => {
                    // Send the clone; scan after the send succeeded, so only
                    // chunks that actually reached the client count as served.
                    // Never log content.
                    let shipped = tx.send(Ok(bytes.clone())).await.is_ok();
                    if !shipped {
                        // The client left — e.g. it cancelled a hedged request
                        // that lost the first-token race, or stopped the turn.
                        // Stop reading upstream: nothing will ever consume the
                        // rest, and the provider should not keep generating
                        // into a dead channel.
                        break;
                    }
                    scan_chunk(
                        &mut line_buffer,
                        &bytes,
                        &mut output_shipped,
                        &mut found_usage,
                    );
                }
                Err(e) => {
                    let _ = tx.send(Err(e)).await;
                    break;
                }
            }
        }

        // The stream's final line may lack a trailing newline; scan whatever is
        // held back. One trailing newline always finishes it — the buffer never
        // contains one by construction.
        if !line_buffer.is_empty() {
            scan_chunk(
                &mut line_buffer,
                b"\n",
                &mut output_shipped,
                &mut found_usage,
            );
        }

        // Reconcile the reservation against actual usage after the stream ends.
        // No output ever reached the client ⇒ unserved ⇒ the hold refunds in
        // full. Output was flowing but the stream was cut ⇒ the exact usage died
        // with the stream, so the estimate stands in for the charge.
        let settled_usage = if output_shipped {
            found_usage.or(estimated_usage)
        } else {
            found_usage
        };
        settle(
            ledger,
            wallet_id,
            settled_usage,
            reserved_millicredits,
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

/// Relay a buffered JSON response to the client and reconcile the reservation synchronously.
async fn relay_buffer(
    bytes: Bytes,
    state: &AppState,
    wallet: Wallet,
    model_config: &ModelConfig,
    estimated_usage: Option<UsageBlock>,
    reserved_millicredits: i64,
) -> Result<Response, AppError> {
    let found_usage = usage::extract_from_response_body(&bytes);
    // The full body was relayed — the response was served, whatever the models
    // made of it. When usage extraction finds nothing, the estimate stands in
    // for the charge rather than refunding. (A stream is different: no usage
    // block means the reader left or the upstream cut out. See relay_stream.)
    settle(
        Arc::clone(&state.ledger),
        wallet.id,
        found_usage.or(estimated_usage),
        reserved_millicredits,
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

/// Reconcile the reservation to actual usage: applies the signed delta
/// `actual - reserved` (charge overrun, refund surplus). No-op on zero delta.
///
/// Refunds in full when nothing was observed — an unserved request never costs
/// the user anything. Callers pass what they observed, merging the estimate
/// in when the response was partly or fully served (see relay_stream,
/// relay_buffer).
///
/// Crash exposure: a crash between reserve and settle leaves the hold on the
/// balance unreconciled (it persists in the wallet row). Bounded to one estimate.
/// Tracked in #234.
async fn settle(
    ledger: Arc<dyn CreditLedger>,
    wallet_id: uuid::Uuid,
    actual_usage: Option<UsageBlock>,
    reserved_millicredits: i64,
    model: &ModelConfig,
) {
    let actual_cost = actual_usage
        .map(|u| rates::compute_cost(&u, model))
        .unwrap_or(0);
    apply_delta(ledger, wallet_id, actual_cost - reserved_millicredits).await;
}

/// Refund the full reservation. Used when forwarding failed before any bytes
/// reached the client — an unserved request never costs the user anything.
async fn refund_reservation(
    ledger: &Arc<dyn CreditLedger>,
    wallet_id: uuid::Uuid,
    reserved_millicredits: i64,
) {
    apply_delta(Arc::clone(ledger), wallet_id, -reserved_millicredits).await;
}

/// Apply a signed balance adjustment (positive charges, negative refunds). No-op on
/// zero. A settle failure is an accepted small-loss risk: the user got their response
/// but we couldn't reconcile the hold, so it stays as the charge.
async fn apply_delta(
    ledger: Arc<dyn CreditLedger>,
    wallet_id: uuid::Uuid,
    delta_millicredits: i64,
) {
    if delta_millicredits == 0 {
        return;
    }
    if let Err(e) = ledger.debit(wallet_id, delta_millicredits).await {
        tracing::error!(
            wallet_id = %wallet_id,
            error = %e,
            delta_millicredits,
            "settlement adjustment failed"
        );
    }
}
