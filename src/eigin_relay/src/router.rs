//! Router assembly and middleware layering.
//!
//! Rate limiting is applied as a layer, not per-handler, so every gated route is
//! capped by default. `/health` is deliberately excluded (Scaleway probes it),
//! and the Apple webhook keeps its own retry-cadence limiter.

use std::sync::Arc;

use axum::Router;
use axum::extract::DefaultBodyLimit;
use axum::middleware;
use axum::routing::{get, post};
use tower_http::trace::TraceLayer;

use crate::{
    AppState, enforce_ip_rate_limit, health, log_errors, require_eigin_key, resolve_client_ip,
    security_headers,
};

/// Chat completions carry base64-encoded image attachments, so the default
/// 2 MB Axum body limit rejects legitimate multi-image requests. 10 MB
/// comfortably covers several normalised images while still bounding request
/// size on this anonymous, open endpoint.
const MAX_REQUEST_BODY_BYTES: usize = 10 * 1024 * 1024;

/// Build the application router with all middleware layered.
pub fn build_router(state: Arc<AppState>) -> Router {
    // All routes gated by the Eigin Relay key. The wallet routes
    // (`/v1/credits/balance`, `/v1/chat/completions`) additionally require a
    // credit token, enforced in-handler by the `WalletBearer` extractor — so at
    // the router level their gate is identical to the key-only routes.
    let key_gated = Router::new()
        .route("/v1/search", get(crate::search::handle))
        .route("/v1/credits/redeem", post(crate::credits::redeem::handle))
        .route(
            "/v1/credits/products",
            get(crate::credits::products::handle),
        )
        // The model catalog is static and free to read, so it needs no wallet — only the relay key.
        .route("/v1/models", get(crate::inference::catalog::handle_list))
        .route("/v1/credits/balance", get(crate::credits::balance::handle))
        .route(
            "/v1/chat/completions",
            post(crate::inference::handler::handle),
        )
        .layer(middleware::from_fn_with_state(
            state.clone(),
            require_eigin_key,
        ));

    // Everything under the blanket per-IP limiter: the key-gated routes plus the
    // public docs. The limiter runs outside the relay-key check, so floods are
    // capped before key validation.
    let rate_limited = Router::new()
        .route("/docs", get(crate::docs::handler))
        .route("/docs/scalar.js", get(crate::docs::scalar::handler))
        .merge(key_gated)
        .layer(middleware::from_fn_with_state(
            state.clone(),
            enforce_ip_rate_limit,
        ));

    Router::new()
        // `/health` is excluded from the blanket limiter — Scaleway probes it for
        // container health. The webhook keeps its own Apple-cadence limiter.
        .route("/health", get(health))
        .route(
            "/webhooks/apple/appstore",
            post(crate::credits::apple::webhook::handle),
        )
        .merge(rate_limited)
        // Resolve the client IP once, before any limiter reads it.
        .layer(middleware::from_fn_with_state(
            state.clone(),
            resolve_client_ip,
        ))
        .layer(TraceLayer::new_for_http())
        .layer(DefaultBodyLimit::max(MAX_REQUEST_BODY_BYTES))
        .layer(middleware::from_fn(log_errors))
        .layer(middleware::from_fn(security_headers))
        .with_state(state)
}
