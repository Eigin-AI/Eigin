//! End-to-end integration tests for the credit system lifecycle.
//!
//! All tests use `InMemoryLedger` + `FakeVerifier` + `httpmock` upstream — no real
//! Apple certificates, no real database, no real upstream provider.
//!
//! Lifecycle covered:
//! - Redeem → balance → chat (stream) → balance reflects debit
//! - Drain to floor → 402
//! - Redeem same transaction again → same token + spent-down balance
//! - Webhook refund → 402 with refunded status
//! - Per-token rate limiting

use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use axum::Router;
use axum::body::to_bytes;
use axum::http::{Request, StatusCode};
use tower::util::ServiceExt;

use eigin_relay::AppState;
use eigin_relay::RateLimiter;
use eigin_relay::credits::InMemoryLedger;
use eigin_relay::inference::catalog::ModelConfig;
use eigin_relay::inference::upstream::UpstreamClient;

mod fakes;
use fakes::apple::FakeVerifier;
use fakes::grant::FakeGrantVerifier;
use fakes::search::NoopSearch;
use fakes::upstream::{BufferUpstream, CapturingUpstream, FakeUpstream};

// ── Test helpers ──────────────────────────────────────────────────────────────

fn test_model() -> ModelConfig {
    ModelConfig {
        id: "test-model".into(),
        provider: "default".into(),
        upstream_id: None,
        aliases: vec![],
        // 10_000mc per 1M input tokens, 20_000mc per 1M output tokens
        input_millicredits_per_1m_tokens: 10_000u64,
        cached_input_millicredits_per_1m_tokens: 0u64,
        output_millicredits_per_1m_tokens: 20_000u64,
    }
}

async fn make_state(
    verifier: FakeVerifier,
    product_credits: HashMap<String, i64>,
    upstream: impl UpstreamClient + 'static,
    _initial_balance_millicredits: i64,
    admit_floor_millicredits: i64,
) -> Arc<AppState> {
    let mut canonical_models = HashMap::new();
    canonical_models.insert("test-model".to_string(), test_model());
    let mut alias_map = HashMap::new();
    alias_map.insert("test-model".to_string(), "test-model".to_string());

    let mut provider_clients = HashMap::new();
    provider_clients.insert(
        "default".to_string(),
        Arc::new(upstream) as Arc<dyn UpstreamClient>,
    );
    let mut provider_keys = HashMap::new();
    provider_keys.insert("default".to_string(), "test-key".to_string());

    Arc::new(AppState {
        search_client: Arc::new(NoopSearch),
        mojeek_api_key: String::new(),
        eigin_relay_keys: vec!["relay-key".into()],
        ip_rate_limiter: RateLimiter::new(100, Duration::from_secs(60)),
        trusted_proxy_hops: 1,
        webhook_rate_limiter: RateLimiter::new(100, Duration::from_secs(60)),
        search_pool_max: 1000,
        search_window: Duration::from_secs(30 * 24 * 60 * 60),
        quota: Arc::new(eigin_relay::quota::InMemoryQuota::default()),
        ledger: Arc::new(InMemoryLedger::default()),
        apple_verifier: Arc::new(verifier),
        grant_verifier: Arc::new(FakeGrantVerifier::failing()),
        product_credits,
        token_encryption_key: [0u8; 32],
        token_encryption_key_secondary: None,
        sandbox_budget_credits: 25_000,
        sandbox_budget_window: Duration::from_secs(30 * 24 * 60 * 60),
        provider_clients,
        provider_keys,
        canonical_models,
        alias_map,
        admit_floor_millicredits,
        token_rate_limiter: RateLimiter::new(100, Duration::from_secs(60)),
        assets_config: HashMap::new(),
        assets_cache: Default::default(),
        asset_store: Arc::new(eigin_relay::assets::store::InertAssetStore),
        presign_expiry: Duration::from_secs(86_400),
    })
}

// Exercise the real, fully-layered router so credit-flow tests run through the
// deployed middleware stack (client-IP resolution + blanket per-IP limiting).
fn build_router(state: Arc<AppState>) -> Router {
    eigin_relay::build_router(state)
}

async fn redeem(app: &Router, jws: &str) -> serde_json::Value {
    let connect_info = axum::extract::ConnectInfo(std::net::SocketAddr::from(([127, 0, 0, 1], 0)));
    let req = Request::builder()
        .method("POST")
        .uri("/v1/credits/redeem")
        .header("x-eigin-key", "relay-key")
        .header("content-type", "application/json")
        .extension(connect_info)
        .body(axum::body::Body::from(
            serde_json::json!({ "type": "apple_iap", "proof": jws }).to_string(),
        ))
        .unwrap();
    let resp = app.clone().oneshot(req).await.unwrap();
    let bytes = to_bytes(resp.into_body(), 4096).await.unwrap();
    serde_json::from_slice(&bytes).unwrap()
}

async fn balance(app: &Router, token: &str) -> (StatusCode, serde_json::Value) {
    let connect_info = axum::extract::ConnectInfo(std::net::SocketAddr::from(([127, 0, 0, 1], 0)));
    let req = Request::builder()
        .uri("/v1/credits/balance")
        .header("x-eigin-key", "relay-key")
        .header("Authorization", format!("Bearer {token}"))
        .extension(connect_info)
        .body(axum::body::Body::empty())
        .unwrap();
    let resp = app.clone().oneshot(req).await.unwrap();
    let status = resp.status();
    let bytes = to_bytes(resp.into_body(), 4096).await.unwrap();
    (status, serde_json::from_slice(&bytes).unwrap())
}

async fn chat(app: &Router, token: &str, model: &str) -> StatusCode {
    let connect_info = axum::extract::ConnectInfo(std::net::SocketAddr::from(([127, 0, 0, 1], 0)));
    let body = serde_json::json!({
        "model": model,
        "stream": true,
        "messages": [{"role": "user", "content": "hi"}]
    });
    let req = Request::builder()
        .method("POST")
        .uri("/v1/chat/completions")
        .header("x-eigin-key", "relay-key")
        .header("Authorization", format!("Bearer {token}"))
        .header("content-type", "application/json")
        .extension(connect_info)
        .body(axum::body::Body::from(body.to_string()))
        .unwrap();
    let resp = app.clone().oneshot(req).await.unwrap();
    // Drain body so the settle task can complete.
    let status = resp.status();
    let _ = to_bytes(resp.into_body(), 65536).await.unwrap();
    // Give the settle task a moment.
    tokio::time::sleep(Duration::from_millis(20)).await;
    status
}

async fn chat_non_streaming(app: &Router, token: &str, model: &str) -> StatusCode {
    let connect_info = axum::extract::ConnectInfo(std::net::SocketAddr::from(([127, 0, 0, 1], 0)));
    let body = serde_json::json!({
        "model": model,
        "stream": false,
        "messages": [{"role": "user", "content": "hi"}]
    });
    let req = Request::builder()
        .method("POST")
        .uri("/v1/chat/completions")
        .header("x-eigin-key", "relay-key")
        .header("Authorization", format!("Bearer {token}"))
        .header("content-type", "application/json")
        .extension(connect_info)
        .body(axum::body::Body::from(body.to_string()))
        .unwrap();
    let resp = app.clone().oneshot(req).await.unwrap();
    let status = resp.status();
    let _ = to_bytes(resp.into_body(), 65536).await.unwrap();
    status
}

async fn webhook_refund(app: &Router, original_tx_id: &str, uuid: &str) -> StatusCode {
    let connect_info = axum::extract::ConnectInfo(std::net::SocketAddr::from(([127, 0, 0, 1], 0)));
    let body = serde_json::json!({ "signedPayload": "fake-signed-payload" });
    let req = Request::builder()
        .method("POST")
        .uri("/webhooks/apple/appstore")
        .header("content-type", "application/json")
        .extension(connect_info)
        .body(axum::body::Body::from(body.to_string()))
        .unwrap();

    // We need a state-aware router with the refund verifier, so this helper is called
    // with a router already configured with the right fake verifier.
    let _ = (original_tx_id, uuid);
    app.clone().oneshot(req).await.unwrap().status()
}

async fn products(app: &Router) -> serde_json::Value {
    let connect_info = axum::extract::ConnectInfo(std::net::SocketAddr::from(([127, 0, 0, 1], 0)));
    let req = Request::builder()
        .uri("/v1/credits/products")
        .header("x-eigin-key", "relay-key")
        .extension(connect_info)
        .body(axum::body::Body::empty())
        .unwrap();
    let resp = app.clone().oneshot(req).await.unwrap();
    let bytes = to_bytes(resp.into_body(), 4096).await.unwrap();
    serde_json::from_slice(&bytes).unwrap()
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[tokio::test]
async fn products_lists_catalog_as_whole_credits_sorted_by_id() {
    let mut product_credits = HashMap::new();
    product_credits.insert("ai.eigin.credits.500".into(), 500_000i64);
    product_credits.insert("ai.eigin.credits.100".into(), 100_000i64);

    let verifier = FakeVerifier::with_transaction("tx-001", "ai.eigin.credits.500");
    let state = make_state(
        verifier,
        product_credits,
        FakeUpstream::with_usage(0, 0),
        0,
        50_000,
    )
    .await;
    let app = build_router(state);

    let json = products(&app).await;
    let items = json["products"].as_array().unwrap();
    assert_eq!(items.len(), 2);
    // Sorted by id: …100 before …500.
    assert_eq!(items[0]["id"], "ai.eigin.credits.100");
    assert_eq!(items[0]["credits"], 100);
    assert_eq!(items[1]["id"], "ai.eigin.credits.500");
    assert_eq!(items[1]["credits"], 500);
}

#[tokio::test]
async fn redeem_mints_wallet_and_returns_token() {
    let mut products = HashMap::new();
    products.insert("ai.eigin.credits.500".into(), 500_000i64);

    let verifier = FakeVerifier::with_transaction("tx-001", "ai.eigin.credits.500");
    let state = make_state(
        verifier,
        products,
        FakeUpstream::with_usage(0, 0),
        0,
        50_000,
    )
    .await;
    let app = build_router(state);

    let json = redeem(&app, "fake-jws").await;
    assert_eq!(json["status"], "active");
    assert_eq!(json["credits"], 500);
    assert!(json["token"].as_str().unwrap().starts_with("eict_"));
}

#[tokio::test]
async fn redeem_same_transaction_returns_same_token_and_spent_down_balance() {
    use eigin_relay::credits::CreditLedger;
    use eigin_relay::credits::token;

    let mut products = HashMap::new();
    products.insert("ai.eigin.credits.500".into(), 500_000i64);

    let ledger: Arc<dyn CreditLedger> = Arc::new(InMemoryLedger::default());

    // First redeem: mint the wallet.
    let state1 = make_state_with_ledger(
        FakeVerifier::with_transaction("tx-same", "ai.eigin.credits.500"),
        products.clone(),
        Arc::clone(&ledger),
    )
    .await;
    let app1 = build_router(state1);
    let first = redeem(&app1, "fake-jws").await;
    let token1 = first["token"].as_str().unwrap().to_owned();
    assert_eq!(first["credits"], 500);

    // Simulate some spend directly on the ledger.
    let hash = token::hash(&token1);
    let wallet = ledger.find_by_token_hash(&hash).await.unwrap().unwrap();
    ledger.debit(wallet.id, 100_000).await.unwrap(); // spend 100 credits

    // Second redeem (restore): same tx id, same ledger — must return same token and spent-down balance.
    let state2 = make_state_with_ledger(
        FakeVerifier::with_transaction("tx-same", "ai.eigin.credits.500"),
        products,
        Arc::clone(&ledger),
    )
    .await;
    let app2 = build_router(state2);
    let second = redeem(&app2, "fake-jws").await;
    let token2 = second["token"].as_str().unwrap().to_owned();

    assert_eq!(token1, token2, "restore must return the same stable token");
    assert_eq!(second["credits"], 400, "balance must reflect prior spend");
}

async fn make_state_with_ledger(
    verifier: FakeVerifier,
    product_credits: HashMap<String, i64>,
    ledger: Arc<dyn eigin_relay::credits::CreditLedger>,
) -> Arc<AppState> {
    let mut canonical_models = HashMap::new();
    canonical_models.insert("test-model".to_string(), test_model());
    let mut alias_map = HashMap::new();
    alias_map.insert("test-model".to_string(), "test-model".to_string());

    let mut provider_clients = HashMap::new();
    provider_clients.insert(
        "default".to_string(),
        Arc::new(FakeUpstream::with_usage(0, 0)) as Arc<dyn UpstreamClient>,
    );
    let mut provider_keys = HashMap::new();
    provider_keys.insert("default".to_string(), "test-key".to_string());

    Arc::new(AppState {
        search_client: Arc::new(NoopSearch),
        mojeek_api_key: String::new(),
        eigin_relay_keys: vec!["relay-key".into()],
        ip_rate_limiter: RateLimiter::new(100, Duration::from_secs(60)),
        trusted_proxy_hops: 1,
        webhook_rate_limiter: RateLimiter::new(100, Duration::from_secs(60)),
        search_pool_max: 1000,
        search_window: Duration::from_secs(30 * 24 * 60 * 60),
        quota: Arc::new(eigin_relay::quota::InMemoryQuota::default()),
        ledger,
        apple_verifier: Arc::new(verifier),
        grant_verifier: Arc::new(FakeGrantVerifier::failing()),
        product_credits,
        token_encryption_key: [0u8; 32],
        token_encryption_key_secondary: None,
        sandbox_budget_credits: 25_000,
        sandbox_budget_window: Duration::from_secs(30 * 24 * 60 * 60),
        provider_clients,
        provider_keys,
        canonical_models,
        alias_map,
        admit_floor_millicredits: 50_000,
        token_rate_limiter: RateLimiter::new(100, Duration::from_secs(60)),
        assets_config: HashMap::new(),
        assets_cache: Default::default(),
        asset_store: Arc::new(eigin_relay::assets::store::InertAssetStore),
        presign_expiry: Duration::from_secs(86_400),
    })
}

async fn make_grant_state(
    grant_verifier: FakeGrantVerifier,
    product_credits: HashMap<String, i64>,
    ledger: Arc<dyn eigin_relay::credits::CreditLedger>,
) -> Arc<AppState> {
    let mut canonical_models = HashMap::new();
    canonical_models.insert("test-model".to_string(), test_model());
    let mut alias_map = HashMap::new();
    alias_map.insert("test-model".to_string(), "test-model".to_string());

    let mut provider_clients = HashMap::new();
    provider_clients.insert(
        "default".to_string(),
        Arc::new(FakeUpstream::with_usage(0, 0)) as Arc<dyn UpstreamClient>,
    );
    let mut provider_keys = HashMap::new();
    provider_keys.insert("default".to_string(), "test-key".to_string());

    Arc::new(AppState {
        search_client: Arc::new(NoopSearch),
        mojeek_api_key: String::new(),
        eigin_relay_keys: vec!["relay-key".into()],
        ip_rate_limiter: RateLimiter::new(100, Duration::from_secs(60)),
        trusted_proxy_hops: 1,
        webhook_rate_limiter: RateLimiter::new(100, Duration::from_secs(60)),
        search_pool_max: 1000,
        search_window: Duration::from_secs(30 * 24 * 60 * 60),
        quota: Arc::new(eigin_relay::quota::InMemoryQuota::default()),
        ledger,
        apple_verifier: Arc::new(FakeVerifier::failing()),
        grant_verifier: Arc::new(grant_verifier),
        product_credits,
        token_encryption_key: [0u8; 32],
        token_encryption_key_secondary: None,
        sandbox_budget_credits: 25_000,
        sandbox_budget_window: Duration::from_secs(30 * 24 * 60 * 60),
        provider_clients,
        provider_keys,
        canonical_models,
        alias_map,
        admit_floor_millicredits: 50_000,
        token_rate_limiter: RateLimiter::new(100, Duration::from_secs(60)),
        assets_config: HashMap::new(),
        assets_cache: Default::default(),
        asset_store: Arc::new(eigin_relay::assets::store::InertAssetStore),
        presign_expiry: Duration::from_secs(86_400),
    })
}

async fn redeem_grant(app: &Router) -> (StatusCode, serde_json::Value) {
    let connect_info = axum::extract::ConnectInfo(std::net::SocketAddr::from(([127, 0, 0, 1], 0)));
    let req = Request::builder()
        .method("POST")
        .uri("/v1/credits/redeem")
        .header("x-eigin-key", "relay-key")
        .header("content-type", "application/json")
        .extension(connect_info)
        .body(axum::body::Body::from(
            serde_json::json!({ "type": "grant", "proof": "fake-jwt" }).to_string(),
        ))
        .unwrap();
    let resp = app.clone().oneshot(req).await.unwrap();
    let status = resp.status();
    let bytes = to_bytes(resp.into_body(), 4096).await.unwrap();
    (status, serde_json::from_slice(&bytes).unwrap())
}

#[tokio::test]
async fn grant_redeem_mints_wallet_and_returns_token() {
    let mut products = HashMap::new();
    products.insert("eigin.credits.v1.grant.500".into(), 500_000i64);

    let verifier =
        FakeGrantVerifier::with_grant("eigin", "grant-001", "eigin.credits.v1.grant.500");
    let state = make_grant_state(verifier, products, Arc::new(InMemoryLedger::default())).await;
    let app = build_router(state);

    let (status, json) = redeem_grant(&app).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["status"], "active");
    assert_eq!(json["credits"], 500);
    assert!(json["token"].as_str().unwrap().starts_with("eict_"));
}

#[tokio::test]
async fn grant_redeem_same_grant_restores_same_token_and_balance() {
    use eigin_relay::credits::CreditLedger;
    use eigin_relay::credits::token;

    let mut products = HashMap::new();
    products.insert("eigin.credits.v1.grant.500".into(), 500_000i64);

    let ledger: Arc<dyn CreditLedger> = Arc::new(InMemoryLedger::default());

    // First redeem: mint.
    let state1 = make_grant_state(
        FakeGrantVerifier::with_grant("eigin", "grant-same", "eigin.credits.v1.grant.500"),
        products.clone(),
        Arc::clone(&ledger),
    )
    .await;
    let (_, first) = redeem_grant(&build_router(state1)).await;
    let token1 = first["token"].as_str().unwrap().to_owned();
    assert_eq!(first["credits"], 500);

    // Spend some credits directly on the ledger.
    let hash = token::hash(&token1);
    let wallet = ledger.find_by_token_hash(&hash).await.unwrap().unwrap();
    ledger.debit(wallet.id, 100_000).await.unwrap();

    // Second redeem of the same grant: same token, spent-down balance.
    let state2 = make_grant_state(
        FakeGrantVerifier::with_grant("eigin", "grant-same", "eigin.credits.v1.grant.500"),
        products,
        Arc::clone(&ledger),
    )
    .await;
    let (_, second) = redeem_grant(&build_router(state2)).await;

    assert_eq!(second["token"].as_str().unwrap(), token1);
    assert_eq!(second["credits"], 400);
}

#[tokio::test]
async fn grant_redeem_unknown_product_returns_400() {
    let verifier =
        FakeGrantVerifier::with_grant("eigin", "grant-002", "eigin.credits.v1.grant.999");
    let state = make_grant_state(
        verifier,
        HashMap::new(),
        Arc::new(InMemoryLedger::default()),
    )
    .await;
    let app = build_router(state);

    let (status, _) = redeem_grant(&app).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn balance_returns_current_credits() {
    let mut products = HashMap::new();
    products.insert("ai.eigin.credits.500".into(), 500_000i64);

    let verifier = FakeVerifier::with_transaction("tx-002", "ai.eigin.credits.500");
    let state = make_state(
        verifier,
        products,
        FakeUpstream::with_usage(0, 0),
        0,
        50_000,
    )
    .await;
    let app = build_router(state);

    let json = redeem(&app, "fake-jws").await;
    let token = json["token"].as_str().unwrap();

    let (status, bal) = balance(&app, token).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(bal["credits"], 500);
    assert_eq!(bal["status"], "active");
}

#[tokio::test]
async fn balance_with_unknown_token_returns_401() {
    let state = make_state(
        FakeVerifier::failing(),
        HashMap::new(),
        FakeUpstream::with_usage(0, 0),
        0,
        50_000,
    )
    .await;
    let app = build_router(state);

    let (status, _) = balance(&app, "eict_unknown").await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn chat_debits_balance_after_stream() {
    let mut products = HashMap::new();
    products.insert("ai.eigin.credits.500".into(), 500_000i64);

    let verifier = FakeVerifier::with_transaction("tx-003", "ai.eigin.credits.500");
    // Upstream reports 1000 prompt tokens (non-cached) + 500 output tokens.
    // Cost = (1000 * 10_000 + 500 * 20_000) / 1_000_000 = 20 millicredits.
    let state = make_state(
        verifier,
        products,
        FakeUpstream::with_usage(1000, 500),
        0,
        50_000,
    )
    .await;
    let app = build_router(Arc::clone(&state));

    let json = redeem(&app, "fake-jws").await;
    let token = json["token"].as_str().unwrap().to_owned();

    let status = chat(&app, &token, "test-model").await;
    assert_eq!(status, StatusCode::OK);

    let (_, bal) = balance(&app, &token).await;
    // 500,000 - 20 = 499,980 millicredits = 499 whole credits (floor division).
    assert_eq!(bal["credits"].as_i64().unwrap(), 499);
}

#[tokio::test]
async fn chat_forwards_prompt_cache_key_to_upstream() {
    let mut products = HashMap::new();
    products.insert("ai.eigin.credits.500".into(), 500_000i64);

    let verifier = FakeVerifier::with_transaction("tx-cache-key", "ai.eigin.credits.500");
    let upstream = CapturingUpstream::default();
    let state = make_state(verifier, products, upstream.clone(), 0, 50_000).await;
    let app = build_router(state);

    let json = redeem(&app, "fake-jws").await;
    let token = json["token"].as_str().unwrap().to_owned();

    // Send a request carrying the OpenAI-style prompt_cache_key.
    let connect_info = axum::extract::ConnectInfo(std::net::SocketAddr::from(([127, 0, 0, 1], 0)));
    let body = serde_json::json!({
        "model": "test-model",
        "stream": true,
        "prompt_cache_key": "chat-abc",
        "messages": [{"role": "user", "content": "hi"}]
    });
    let req = Request::builder()
        .method("POST")
        .uri("/v1/chat/completions")
        .header("x-eigin-key", "relay-key")
        .header("Authorization", format!("Bearer {token}"))
        .header("content-type", "application/json")
        .extension(connect_info)
        .body(axum::body::Body::from(body.to_string()))
        .unwrap();
    let resp = app.clone().oneshot(req).await.unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let _ = to_bytes(resp.into_body(), 65536).await.unwrap();

    // The relay re-serializes the body; the unknown field must survive to the upstream.
    let forwarded = upstream.captured_body().expect("upstream received a body");
    let forwarded: serde_json::Value = serde_json::from_slice(&forwarded).unwrap();
    assert_eq!(forwarded["prompt_cache_key"], "chat-abc");
}

#[tokio::test]
async fn chat_non_streaming_debits_balance() {
    let mut products = HashMap::new();
    products.insert("ai.eigin.credits.500".into(), 500_000i64);

    let verifier = FakeVerifier::with_transaction("tx-003b", "ai.eigin.credits.500");
    // Upstream reports 1000 prompt tokens (non-cached) + 500 output tokens.
    // Cost = (1000 * 10_000 + 500 * 20_000) / 1_000_000 = 20 millicredits.
    let state = make_state(
        verifier,
        products,
        BufferUpstream::with_usage(1000, 500),
        0,
        50_000,
    )
    .await;
    let app = build_router(Arc::clone(&state));

    let json = redeem(&app, "fake-jws").await;
    let token = json["token"].as_str().unwrap().to_owned();

    let status = chat_non_streaming(&app, &token, "test-model").await;
    assert_eq!(status, StatusCode::OK);

    let (_, bal) = balance(&app, &token).await;
    // 500,000 - 20 = 499,980 millicredits = 499 whole credits (floor division).
    assert_eq!(bal["credits"].as_i64().unwrap(), 499);
}

#[tokio::test]
async fn chat_below_floor_returns_402() {
    let mut products = HashMap::new();
    // Mint just 10 credits (10_000 millicredits), floor is 50_000 → immediately blocked.
    products.insert("ai.eigin.credits.small".into(), 10_000i64);

    let verifier = FakeVerifier::with_transaction("tx-004", "ai.eigin.credits.small");
    let state = make_state(
        verifier,
        products,
        FakeUpstream::with_usage(0, 0),
        0,
        50_000,
    )
    .await;
    let app = build_router(state);

    let json = redeem(&app, "fake-jws").await;
    let token = json["token"].as_str().unwrap().to_owned();

    let status = chat(&app, &token, "test-model").await;
    assert_eq!(status, StatusCode::PAYMENT_REQUIRED);
}

#[tokio::test]
async fn chat_with_unknown_model_returns_400() {
    let mut products = HashMap::new();
    products.insert("ai.eigin.credits.500".into(), 500_000i64);

    let verifier = FakeVerifier::with_transaction("tx-005", "ai.eigin.credits.500");
    let state = make_state(
        verifier,
        products,
        FakeUpstream::with_usage(0, 0),
        0,
        50_000,
    )
    .await;
    let app = build_router(state);

    let json = redeem(&app, "fake-jws").await;
    let token = json["token"].as_str().unwrap().to_owned();

    let status = chat(&app, &token, "gpt-unknown-model").await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn webhook_refund_closes_wallet() {
    let mut products = HashMap::new();
    products.insert("ai.eigin.credits.500".into(), 500_000i64);

    let tx_id = "tx-refund-001";
    let notification_uuid = "notif-uuid-001";

    // First: mint a wallet via redeem.
    let verifier = FakeVerifier::with_transaction(tx_id, "ai.eigin.credits.500");
    let ledger: Arc<dyn eigin_relay::credits::CreditLedger> = Arc::new(InMemoryLedger::default());

    let state = make_state_with_ledger(verifier, products.clone(), Arc::clone(&ledger)).await;
    let app = build_router(Arc::clone(&state));
    let json = redeem(&app, "fake-jws").await;
    let token = json["token"].as_str().unwrap().to_owned();

    // Confirm wallet is active.
    let (_, bal) = balance(&app, &token).await;
    assert_eq!(bal["status"], "active");

    // Now send a refund webhook. We need a new state with a refund verifier.
    let refund_state = make_state_with_ledger(
        FakeVerifier::with_refund_notification(tx_id, notification_uuid),
        products,
        Arc::clone(&ledger),
    )
    .await;
    let refund_app = build_router(refund_state);

    let wh_status = webhook_refund(&refund_app, tx_id, notification_uuid).await;
    assert_eq!(wh_status, StatusCode::OK);

    // Balance check on same token now shows refunded status.
    let (_, bal_after) = balance(&app, &token).await;
    assert_eq!(bal_after["status"], "refunded");
    assert_eq!(bal_after["credits"], 0);
}

#[tokio::test]
async fn webhook_refund_is_idempotent() {
    let mut products = HashMap::new();
    products.insert("ai.eigin.credits.500".into(), 500_000i64);
    let tx_id = "tx-refund-002";
    let notification_uuid = "notif-uuid-002";
    let ledger: Arc<dyn eigin_relay::credits::CreditLedger> = Arc::new(InMemoryLedger::default());

    // Mint wallet.
    let state1 = make_state_with_ledger(
        FakeVerifier::with_transaction(tx_id, "ai.eigin.credits.500"),
        products.clone(),
        Arc::clone(&ledger),
    )
    .await;
    let app1 = build_router(state1);
    redeem(&app1, "fake-jws").await;

    // Send refund twice — both must return 200.
    for _ in 0..2 {
        let state = make_state_with_ledger(
            FakeVerifier::with_refund_notification(tx_id, notification_uuid),
            products.clone(),
            Arc::clone(&ledger),
        )
        .await;
        let app = build_router(state);
        let status = webhook_refund(&app, tx_id, notification_uuid).await;
        assert_eq!(status, StatusCode::OK);
    }
}

#[tokio::test]
async fn chat_after_refund_returns_402() {
    let mut products = HashMap::new();
    products.insert("ai.eigin.credits.500".into(), 500_000i64);
    let tx_id = "tx-refund-003";
    let ledger: Arc<dyn eigin_relay::credits::CreditLedger> = Arc::new(InMemoryLedger::default());

    let state = make_state_with_ledger(
        FakeVerifier::with_transaction(tx_id, "ai.eigin.credits.500"),
        products.clone(),
        Arc::clone(&ledger),
    )
    .await;
    let app = build_router(Arc::clone(&state));
    let json = redeem(&app, "fake-jws").await;
    let token = json["token"].as_str().unwrap().to_owned();

    // Refund.
    let refund_state = make_state_with_ledger(
        FakeVerifier::with_refund_notification(tx_id, "notif-003"),
        products,
        Arc::clone(&ledger),
    )
    .await;
    let refund_app = build_router(refund_state);
    webhook_refund(&refund_app, tx_id, "notif-003").await;

    // Attempting to chat with the refunded wallet must fail with 402.
    let status = chat(&app, &token, "test-model").await;
    assert_eq!(status, StatusCode::PAYMENT_REQUIRED);
}

#[tokio::test]
async fn webhook_rate_limited_after_limit() {
    let mut products = HashMap::new();
    products.insert("ai.eigin.credits.500".into(), 500_000i64);

    let mut canonical_models = HashMap::new();
    canonical_models.insert("test-model".to_string(), test_model());
    let mut alias_map = HashMap::new();
    alias_map.insert("test-model".to_string(), "test-model".to_string());
    let mut provider_clients = HashMap::new();
    provider_clients.insert(
        "default".to_string(),
        Arc::new(FakeUpstream::with_usage(0, 0)) as Arc<dyn UpstreamClient>,
    );
    let mut provider_keys = HashMap::new();
    provider_keys.insert("default".to_string(), "test-key".to_string());

    // Tight limit so the test can flood it deterministically.
    let state = Arc::new(AppState {
        search_client: Arc::new(NoopSearch),
        mojeek_api_key: String::new(),
        eigin_relay_keys: vec!["relay-key".into()],
        ip_rate_limiter: RateLimiter::new(100, Duration::from_secs(60)),
        trusted_proxy_hops: 1,
        webhook_rate_limiter: RateLimiter::new(2, Duration::from_secs(60)),
        search_pool_max: 1000,
        search_window: Duration::from_secs(30 * 24 * 60 * 60),
        quota: Arc::new(eigin_relay::quota::InMemoryQuota::default()),
        ledger: Arc::new(InMemoryLedger::default()),
        apple_verifier: Arc::new(FakeVerifier::failing()),
        grant_verifier: Arc::new(FakeGrantVerifier::failing()),
        product_credits: products,
        token_encryption_key: [0u8; 32],
        token_encryption_key_secondary: None,
        sandbox_budget_credits: 25_000,
        sandbox_budget_window: Duration::from_secs(30 * 24 * 60 * 60),
        provider_clients,
        provider_keys,
        canonical_models,
        alias_map,
        admit_floor_millicredits: 50_000,
        token_rate_limiter: RateLimiter::new(100, Duration::from_secs(60)),
        assets_config: HashMap::new(),
        assets_cache: Default::default(),
        asset_store: Arc::new(eigin_relay::assets::store::InertAssetStore),
        presign_expiry: Duration::from_secs(86_400),
    });
    let app = build_router(state);

    // First two requests exhaust the limit (verification fails, but that's after
    // the rate check, so it still counts and returns 200 per Apple's contract).
    assert_eq!(
        webhook_refund(&app, "tx-flood", "notif-flood-1").await,
        StatusCode::OK
    );
    assert_eq!(
        webhook_refund(&app, "tx-flood", "notif-flood-2").await,
        StatusCode::OK
    );
    // Third request from the same IP within the window is rate limited.
    assert_eq!(
        webhook_refund(&app, "tx-flood", "notif-flood-3").await,
        StatusCode::TOO_MANY_REQUESTS
    );
}

#[tokio::test]
async fn webhook_malformed_body_returns_ok() {
    // A body that isn't valid JSON must still return 200 — Apple retries on
    // non-2xx, and a payload that will never parse should not be retried.
    let mut products = HashMap::new();
    products.insert("ai.eigin.credits.500".into(), 500_000i64);
    let state = make_state_with_ledger(
        FakeVerifier::failing(),
        products,
        Arc::new(InMemoryLedger::default()),
    )
    .await;
    let app = build_router(state);

    let connect_info = axum::extract::ConnectInfo(std::net::SocketAddr::from(([127, 0, 0, 1], 0)));
    let req = Request::builder()
        .method("POST")
        .uri("/webhooks/apple/appstore")
        .header("content-type", "application/json")
        .extension(connect_info)
        .body(axum::body::Body::from("not json at all"))
        .unwrap();

    let status = app.oneshot(req).await.unwrap().status();
    assert_eq!(status, StatusCode::OK);
}

// ── Notification freshness ───────────────────────────────────────────────────

#[tokio::test]
async fn webhook_rejects_stale_signed_date_and_takes_no_action() {
    let mut products = HashMap::new();
    products.insert("ai.eigin.credits.500".into(), 500_000i64);
    let tx_id = "tx-stale-001";
    let ledger: Arc<dyn eigin_relay::credits::CreditLedger> = Arc::new(InMemoryLedger::default());

    let state = make_state_with_ledger(
        FakeVerifier::with_transaction(tx_id, "ai.eigin.credits.500"),
        products.clone(),
        Arc::clone(&ledger),
    )
    .await;
    let app = build_router(Arc::clone(&state));
    let token = redeem(&app, "fake-jws").await["token"]
        .as_str()
        .unwrap()
        .to_owned();

    // A refund notification signed 8 days ago — outside the 7-day window.
    let stale = time::OffsetDateTime::now_utc() - time::Duration::days(8);
    let refund_state = make_state_with_ledger(
        FakeVerifier::with_refund_notification(tx_id, "notif-stale").signed_at(stale),
        products,
        Arc::clone(&ledger),
    )
    .await;
    let refund_app = build_router(refund_state);

    // Still 200 (Apple must not retry), but the wallet is untouched.
    let status = webhook_refund(&refund_app, tx_id, "notif-stale").await;
    assert_eq!(status, StatusCode::OK);

    let (_, bal) = balance(&app, &token).await;
    assert_eq!(bal["status"], "active");
}

#[tokio::test]
async fn webhook_accepts_signed_date_within_the_window() {
    let mut products = HashMap::new();
    products.insert("ai.eigin.credits.500".into(), 500_000i64);
    let tx_id = "tx-fresh-001";
    let ledger: Arc<dyn eigin_relay::credits::CreditLedger> = Arc::new(InMemoryLedger::default());

    let state = make_state_with_ledger(
        FakeVerifier::with_transaction(tx_id, "ai.eigin.credits.500"),
        products.clone(),
        Arc::clone(&ledger),
    )
    .await;
    let app = build_router(Arc::clone(&state));
    redeem(&app, "fake-jws").await;

    // Signed 6 days ago — inside the 7-day window, mirroring a genuine Apple retry.
    let almost_stale = time::OffsetDateTime::now_utc() - time::Duration::days(6);
    let refund_state = make_state_with_ledger(
        FakeVerifier::with_refund_notification(tx_id, "notif-fresh").signed_at(almost_stale),
        products,
        Arc::clone(&ledger),
    )
    .await;
    let refund_app = build_router(refund_state);

    webhook_refund(&refund_app, tx_id, "notif-fresh").await;

    // A notification inside the window is acted on: the wallet closes.
    let fingerprint = eigin_relay::credits::token::hash(tx_id);
    let wallet = ledger
        .find_by_fingerprint(
            &eigin_relay::credits::ledger::WalletOrigin::AppleAppStore,
            &fingerprint,
        )
        .await
        .unwrap()
        .expect("wallet exists");
    assert_eq!(
        wallet.status,
        eigin_relay::credits::ledger::WalletStatus::Refunded
    );
}

#[tokio::test]
async fn webhook_rejects_future_signed_date_beyond_skew_tolerance() {
    let mut products = HashMap::new();
    products.insert("ai.eigin.credits.500".into(), 500_000i64);
    let tx_id = "tx-future-001";
    let ledger: Arc<dyn eigin_relay::credits::CreditLedger> = Arc::new(InMemoryLedger::default());

    let state = make_state_with_ledger(
        FakeVerifier::with_transaction(tx_id, "ai.eigin.credits.500"),
        products.clone(),
        Arc::clone(&ledger),
    )
    .await;
    let app = build_router(Arc::clone(&state));
    let token = redeem(&app, "fake-jws").await["token"]
        .as_str()
        .unwrap()
        .to_owned();

    // Signed 1 hour in the future — well beyond the 5-minute skew tolerance.
    let future = time::OffsetDateTime::now_utc() + time::Duration::hours(1);
    let refund_state = make_state_with_ledger(
        FakeVerifier::with_refund_notification(tx_id, "notif-future").signed_at(future),
        products,
        Arc::clone(&ledger),
    )
    .await;
    let refund_app = build_router(refund_state);

    let status = webhook_refund(&refund_app, tx_id, "notif-future").await;
    assert_eq!(status, StatusCode::OK);

    let (_, bal) = balance(&app, &token).await;
    assert_eq!(bal["status"], "active");
}

#[tokio::test]
async fn webhook_rejects_missing_signed_date() {
    let mut products = HashMap::new();
    products.insert("ai.eigin.credits.500".into(), 500_000i64);
    let tx_id = "tx-nodate-001";
    let ledger: Arc<dyn eigin_relay::credits::CreditLedger> = Arc::new(InMemoryLedger::default());

    let state = make_state_with_ledger(
        FakeVerifier::with_transaction(tx_id, "ai.eigin.credits.500"),
        products.clone(),
        Arc::clone(&ledger),
    )
    .await;
    let app = build_router(Arc::clone(&state));
    let token = redeem(&app, "fake-jws").await["token"]
        .as_str()
        .unwrap()
        .to_owned();

    let refund_state = make_state_with_ledger(
        FakeVerifier::with_refund_notification(tx_id, "notif-nodate").without_signed_date(),
        products,
        Arc::clone(&ledger),
    )
    .await;
    let refund_app = build_router(refund_state);

    let status = webhook_refund(&refund_app, tx_id, "notif-nodate").await;
    assert_eq!(status, StatusCode::OK);

    let (_, bal) = balance(&app, &token).await;
    assert_eq!(bal["status"], "active");
}

// ── Sandbox issuance budget ─────────────────────────────────────────────────────

use eigin_relay::Quota;
use eigin_relay::credits::apple::AppleEnvironment;

/// State sharing a ledger + quota across redeems, with a configurable sandbox budget.
async fn make_sandbox_state(
    verifier: FakeVerifier,
    product_credits: HashMap<String, i64>,
    ledger: Arc<dyn eigin_relay::credits::CreditLedger>,
    quota: Arc<dyn Quota>,
    sandbox_budget_credits: u64,
) -> Arc<AppState> {
    Arc::new(AppState {
        search_client: Arc::new(NoopSearch),
        mojeek_api_key: String::new(),
        eigin_relay_keys: vec!["relay-key".into()],
        ip_rate_limiter: RateLimiter::new(100, Duration::from_secs(60)),
        trusted_proxy_hops: 1,
        webhook_rate_limiter: RateLimiter::new(100, Duration::from_secs(60)),
        search_pool_max: 1000,
        search_window: Duration::from_secs(30 * 24 * 60 * 60),
        quota,
        ledger,
        apple_verifier: Arc::new(verifier),
        grant_verifier: Arc::new(FakeGrantVerifier::failing()),
        product_credits,
        token_encryption_key: [0u8; 32],
        token_encryption_key_secondary: None,
        sandbox_budget_credits,
        sandbox_budget_window: Duration::from_secs(30 * 24 * 60 * 60),
        provider_clients: HashMap::new(),
        provider_keys: HashMap::new(),
        canonical_models: HashMap::new(),
        alias_map: HashMap::new(),
        admit_floor_millicredits: 50_000,
        token_rate_limiter: RateLimiter::new(100, Duration::from_secs(60)),
        assets_config: HashMap::new(),
        assets_cache: Default::default(),
        asset_store: Arc::new(eigin_relay::assets::store::InertAssetStore),
        presign_expiry: Duration::from_secs(86_400),
    })
}

fn credits_500() -> HashMap<String, i64> {
    let mut products = HashMap::new();
    products.insert("ai.eigin.credits.500".into(), 500_000i64);
    products
}

async fn redeem_status(app: &Router) -> StatusCode {
    let connect_info = axum::extract::ConnectInfo(std::net::SocketAddr::from(([127, 0, 0, 1], 0)));
    let req = Request::builder()
        .method("POST")
        .uri("/v1/credits/redeem")
        .header("x-eigin-key", "relay-key")
        .header("content-type", "application/json")
        .extension(connect_info)
        .body(axum::body::Body::from(
            serde_json::json!({ "type": "apple_iap", "proof": "fake-jws" }).to_string(),
        ))
        .unwrap();
    app.clone().oneshot(req).await.unwrap().status()
}

#[tokio::test]
async fn sandbox_redeems_until_budget_then_rejected() {
    use eigin_relay::quota::InMemoryQuota;

    let ledger: Arc<dyn eigin_relay::credits::CreditLedger> = Arc::new(InMemoryLedger::default());
    let quota: Arc<dyn Quota> = Arc::new(InMemoryQuota::default());

    // Budget of 1000 credits admits exactly two 500-credit sandbox wallets.
    for tx in ["sb-a", "sb-b"] {
        let state = make_sandbox_state(
            FakeVerifier::with_transaction_env(
                tx,
                "ai.eigin.credits.500",
                AppleEnvironment::Sandbox,
            ),
            credits_500(),
            Arc::clone(&ledger),
            Arc::clone(&quota),
            1000,
        )
        .await;
        assert_eq!(redeem_status(&build_router(state)).await, StatusCode::OK);
    }

    // A third distinct sandbox purchase would exceed the budget.
    let state = make_sandbox_state(
        FakeVerifier::with_transaction_env(
            "sb-c",
            "ai.eigin.credits.500",
            AppleEnvironment::Sandbox,
        ),
        credits_500(),
        Arc::clone(&ledger),
        Arc::clone(&quota),
        1000,
    )
    .await;
    assert_eq!(
        redeem_status(&build_router(state)).await,
        StatusCode::TOO_MANY_REQUESTS
    );
}

#[tokio::test]
async fn sandbox_restore_does_not_consume_budget() {
    use eigin_relay::quota::InMemoryQuota;

    let ledger: Arc<dyn eigin_relay::credits::CreditLedger> = Arc::new(InMemoryLedger::default());
    let quota: Arc<dyn Quota> = Arc::new(InMemoryQuota::default());

    // Budget of exactly one 500-credit wallet.
    let mint = |tx: &'static str| {
        let ledger = Arc::clone(&ledger);
        let quota = Arc::clone(&quota);
        async move {
            let state = make_sandbox_state(
                FakeVerifier::with_transaction_env(
                    tx,
                    "ai.eigin.credits.500",
                    AppleEnvironment::Sandbox,
                ),
                credits_500(),
                ledger,
                quota,
                500,
            )
            .await;
            redeem_status(&build_router(state)).await
        }
    };

    // First mint consumes the whole budget.
    assert_eq!(mint("sb-restore").await, StatusCode::OK);
    // Re-redeeming the SAME transaction restores without drawing budget again.
    assert_eq!(mint("sb-restore").await, StatusCode::OK);
    // A different transaction is now over budget.
    assert_eq!(mint("sb-other").await, StatusCode::TOO_MANY_REQUESTS);
}

#[tokio::test]
async fn sandbox_refund_closes_only_the_sandbox_wallet() {
    use eigin_relay::quota::InMemoryQuota;

    // Same originalTransactionId in both environments — they are distinct wallets.
    let tx_id = "tx-shared-id";
    let ledger: Arc<dyn eigin_relay::credits::CreditLedger> = Arc::new(InMemoryLedger::default());
    let quota: Arc<dyn Quota> = Arc::new(InMemoryQuota::default());

    // Mint a production wallet.
    let prod_state = make_sandbox_state(
        FakeVerifier::with_transaction_env(
            tx_id,
            "ai.eigin.credits.500",
            AppleEnvironment::Production,
        ),
        credits_500(),
        Arc::clone(&ledger),
        Arc::clone(&quota),
        25_000,
    )
    .await;
    let prod_app = build_router(prod_state);
    let prod_token = redeem(&prod_app, "fake-jws").await["token"]
        .as_str()
        .unwrap()
        .to_owned();

    // Mint a sandbox wallet with the same transaction id.
    let sb_state = make_sandbox_state(
        FakeVerifier::with_transaction_env(
            tx_id,
            "ai.eigin.credits.500",
            AppleEnvironment::Sandbox,
        ),
        credits_500(),
        Arc::clone(&ledger),
        Arc::clone(&quota),
        25_000,
    )
    .await;
    let sb_app = build_router(sb_state);
    let sb_token = redeem(&sb_app, "fake-jws").await["token"]
        .as_str()
        .unwrap()
        .to_owned();

    // A sandbox refund notification arrives.
    let refund_state = make_sandbox_state(
        FakeVerifier::with_refund_notification_env(tx_id, "notif-sb", AppleEnvironment::Sandbox),
        credits_500(),
        Arc::clone(&ledger),
        Arc::clone(&quota),
        25_000,
    )
    .await;
    webhook_refund(&build_router(refund_state), tx_id, "notif-sb").await;

    // Sandbox wallet is refunded; production wallet is untouched.
    let (_, sb_bal) = balance(&sb_app, &sb_token).await;
    assert_eq!(sb_bal["status"], "refunded");
    let (_, prod_bal) = balance(&prod_app, &prod_token).await;
    assert_eq!(prod_bal["status"], "active");
}

#[tokio::test]
async fn production_redeem_is_never_budget_gated() {
    use eigin_relay::quota::InMemoryQuota;

    let ledger: Arc<dyn eigin_relay::credits::CreditLedger> = Arc::new(InMemoryLedger::default());
    let quota: Arc<dyn Quota> = Arc::new(InMemoryQuota::default());

    // Budget of zero would block any sandbox redeem, but production is exempt.
    for tx in ["prod-a", "prod-b", "prod-c"] {
        let state = make_sandbox_state(
            FakeVerifier::with_transaction_env(
                tx,
                "ai.eigin.credits.500",
                AppleEnvironment::Production,
            ),
            credits_500(),
            Arc::clone(&ledger),
            Arc::clone(&quota),
            0,
        )
        .await;
        assert_eq!(redeem_status(&build_router(state)).await, StatusCode::OK);
    }
}
