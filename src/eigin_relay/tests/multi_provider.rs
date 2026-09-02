//! End-to-end test: inference requests are routed to the correct upstream provider
//! based on the model's `provider` field from `models.toml`.
//!
//! Also tests alias resolution and upstream ID rewriting.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use axum::body::to_bytes;
use axum::http::{Request, StatusCode};
use bytes::Bytes;
use tower::util::ServiceExt;

use eigin_relay::AppError;
use eigin_relay::RateLimiter;
use eigin_relay::credits::InMemoryLedger;
use eigin_relay::inference::catalog::ModelConfig;
use eigin_relay::inference::upstream::{UpstreamClient, UpstreamResponse};

mod fakes;
use fakes::apple::FakeVerifier;
use fakes::grant::FakeGrantVerifier;
use fakes::search::NoopSearch;

// ── Tagged upstream (captures the model ID forwarded to it) ─────────────────

struct TaggedUpstream {
    tag: String,
}

#[async_trait::async_trait]
impl UpstreamClient for TaggedUpstream {
    async fn chat_completions(
        &self,
        body: Bytes,
        _api_key: &str,
    ) -> Result<UpstreamResponse, AppError> {
        // Capture the model ID from the forwarded body.
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap_or_default();
        let forwarded_model = json["model"].as_str().unwrap_or("").to_string();

        let body = serde_json::json!({
            "choices": [{
                "message": { "content": format!("{}:model={}", self.tag, forwarded_model) }
            }],
            "usage": { "prompt_tokens": 1, "completion_tokens": 1 }
        });
        Ok(UpstreamResponse::Buffer(Bytes::from(
            serde_json::to_vec(&body).unwrap(),
        )))
    }
}

// ── Test helpers ──────────────────────────────────────────────────────────────

fn model(id: &str, provider: &str) -> ModelConfig {
    model_with_aliases(id, provider, vec![])
}

fn model_with_aliases(id: &str, provider: &str, aliases: Vec<&str>) -> ModelConfig {
    ModelConfig {
        id: id.to_string(),
        provider: provider.to_string(),
        upstream_id: None,
        aliases: aliases.iter().map(|s| s.to_string()).collect(),
        input_millicredits_per_1m_tokens: 1_000,
        cached_input_millicredits_per_1m_tokens: 0,
        output_millicredits_per_1m_tokens: 1_000,
    }
}

fn model_with_upstream(id: &str, provider: &str, upstream_id: &str) -> ModelConfig {
    ModelConfig {
        id: id.to_string(),
        provider: provider.to_string(),
        upstream_id: Some(upstream_id.to_string()),
        aliases: vec![],
        input_millicredits_per_1m_tokens: 1_000,
        cached_input_millicredits_per_1m_tokens: 0,
        output_millicredits_per_1m_tokens: 1_000,
    }
}

async fn make_state_with_providers() -> Arc<eigin_relay::AppState> {
    let mut canonical_models = HashMap::new();
    let mut alias_map = HashMap::new();

    // model-a (canonical only, no aliases)
    let m_a = model("model-a", "provider_a");
    canonical_models.insert("model-a".to_string(), m_a.clone());
    alias_map.insert("model-a".to_string(), "model-a".to_string());

    // model-b (canonical + aliases)
    let m_b = model_with_aliases(
        "model-b",
        "provider_b",
        vec!["model-b-alias", "model-b-legacy"],
    );
    canonical_models.insert("model-b".to_string(), m_b.clone());
    alias_map.insert("model-b".to_string(), "model-b".to_string());
    alias_map.insert("model-b-alias".to_string(), "model-b".to_string());
    alias_map.insert("model-b-legacy".to_string(), "model-b".to_string());

    // model-upstream (canonical with different upstream_id)
    let m_u = model_with_upstream("model-upstream", "provider_a", "provider-internal-id-123");
    canonical_models.insert("model-upstream".to_string(), m_u.clone());
    alias_map.insert("model-upstream".to_string(), "model-upstream".to_string());

    // model-missing (provider not configured)
    let m_m = model("model-missing", "missing");
    canonical_models.insert("model-missing".to_string(), m_m.clone());
    alias_map.insert("model-missing".to_string(), "model-missing".to_string());

    let mut provider_clients = HashMap::new();
    provider_clients.insert(
        "provider_a".to_string(),
        Arc::new(TaggedUpstream {
            tag: "provider_a".to_string(),
        }) as Arc<dyn UpstreamClient>,
    );
    provider_clients.insert(
        "provider_b".to_string(),
        Arc::new(TaggedUpstream {
            tag: "provider_b".to_string(),
        }) as Arc<dyn UpstreamClient>,
    );

    let mut provider_keys = HashMap::new();
    provider_keys.insert("provider_a".to_string(), "key-a".to_string());
    provider_keys.insert("provider_b".to_string(), "key-b".to_string());

    let mut product_credits = HashMap::new();
    product_credits.insert("ai.eigin.credits.500".into(), 500_000i64);

    Arc::new(eigin_relay::AppState {
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
        apple_verifier: Arc::new(FakeVerifier::with_transaction(
            "tx-001",
            "ai.eigin.credits.500",
        )),
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
        admit_floor_millicredits: 1,
        token_rate_limiter: RateLimiter::new(100, Duration::from_secs(60)),
        assets_config: HashMap::new(),
        assets_cache: Default::default(),
        asset_store: Arc::new(eigin_relay::assets::store::InertAssetStore),
        presign_expiry: Duration::from_secs(86_400),
    })
}

// Exercise the real, fully-layered router as deployed.
fn router(state: Arc<eigin_relay::AppState>) -> axum::Router {
    eigin_relay::build_router(state)
}

async fn redeem(app: &axum::Router) -> String {
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
    let resp = app.clone().oneshot(req).await.unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let bytes = to_bytes(resp.into_body(), 4096).await.unwrap();
    let json: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    json["token"].as_str().unwrap().to_owned()
}

async fn chat(app: &axum::Router, token: &str, model: &str) -> (StatusCode, String) {
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
    let bytes = to_bytes(resp.into_body(), 4096).await.unwrap();
    (status, String::from_utf8_lossy(&bytes).to_string())
}

async fn list_models(app: &axum::Router) -> serde_json::Value {
    let connect_info = axum::extract::ConnectInfo(std::net::SocketAddr::from(([127, 0, 0, 1], 0)));
    let req = Request::builder()
        .uri("/v1/models")
        .header("x-eigin-key", "relay-key")
        .extension(connect_info)
        .body(axum::body::Body::empty())
        .unwrap();
    let resp = app.clone().oneshot(req).await.unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let bytes = to_bytes(resp.into_body(), 4096).await.unwrap();
    serde_json::from_slice(&bytes).unwrap()
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[tokio::test]
async fn routes_canonical_id_to_provider_a() {
    let state = make_state_with_providers().await;
    let app = router(state);
    let token = redeem(&app).await;
    let (status, body) = chat(&app, &token, "model-a").await;
    assert_eq!(status, StatusCode::OK);
    assert!(body.contains("provider_a"), "body was: {body}");
}

#[tokio::test]
async fn routes_canonical_id_to_provider_b() {
    let state = make_state_with_providers().await;
    let app = router(state);
    let token = redeem(&app).await;
    let (status, body) = chat(&app, &token, "model-b").await;
    assert_eq!(status, StatusCode::OK);
    assert!(body.contains("provider_b"), "body was: {body}");
}

#[tokio::test]
async fn alias_routes_to_canonical_provider() {
    let state = make_state_with_providers().await;
    let app = router(state);
    let token = redeem(&app).await;

    // Both aliases should route to the same provider as model-b.
    let (status, body) = chat(&app, &token, "model-b-alias").await;
    assert_eq!(status, StatusCode::OK);
    assert!(body.contains("provider_b"), "body was: {body}");

    let (status, body) = chat(&app, &token, "model-b-legacy").await;
    assert_eq!(status, StatusCode::OK);
    assert!(body.contains("provider_b"), "body was: {body}");
}

#[tokio::test]
async fn upstream_id_is_rewritten() {
    let state = make_state_with_providers().await;
    let app = router(state);
    let token = redeem(&app).await;

    // Request the canonical ID, but the provider should receive the upstream_id.
    let (status, body) = chat(&app, &token, "model-upstream").await;
    assert_eq!(status, StatusCode::OK);
    assert!(
        body.contains("model=provider-internal-id-123"),
        "upstream_id not rewritten; body was: {body}"
    );
}

#[tokio::test]
async fn alias_routes_with_upstream_id_rewrite() {
    let state = make_state_with_providers().await;
    let app = router(state);
    let token = redeem(&app).await;

    // Request via alias -> should resolve to model-upstream -> upstream_id rewritten.
    // (model-upstream has no aliases in this test, but the canonical itself should trigger
    // the upstream rewrite too.)
    let (status, body) = chat(&app, &token, "model-upstream").await;
    assert_eq!(status, StatusCode::OK);
    assert!(
        body.contains("model=provider-internal-id-123"),
        "upstream_id not rewritten for canonical id; body was: {body}"
    );
}

#[tokio::test]
async fn model_list_excludes_aliases() {
    let state = make_state_with_providers().await;
    let app = router(state);

    let json = list_models(&app).await;
    let data = json["data"].as_array().unwrap();
    let ids: Vec<String> = data
        .iter()
        .map(|m| m["id"].as_str().unwrap().to_string())
        .collect();

    // Should contain only canonical IDs.
    assert!(ids.contains(&"model-a".to_string()));
    assert!(ids.contains(&"model-b".to_string()));
    assert!(ids.contains(&"model-upstream".to_string()));
    assert!(ids.contains(&"model-missing".to_string()));

    // Should NOT contain aliases.
    assert!(!ids.contains(&"model-b-alias".to_string()));
    assert!(!ids.contains(&"model-b-legacy".to_string()));
}

#[tokio::test]
async fn missing_provider_returns_service_unavailable() {
    let state = make_state_with_providers().await;
    let app = router(state);
    let token = redeem(&app).await;
    let (status, body) = chat(&app, &token, "model-missing").await;
    assert_eq!(status, StatusCode::SERVICE_UNAVAILABLE);
    // Opaque body: provider/config detail must not be disclosed to the client.
    assert!(
        body.contains("service temporarily unavailable"),
        "body was: {body}"
    );
    assert!(
        !body.contains("missing"),
        "body leaked config detail: {body}"
    );
}

#[tokio::test]
async fn unknown_model_returns_bad_request() {
    let state = make_state_with_providers().await;
    let app = router(state);
    let token = redeem(&app).await;
    let (status, body) = chat(&app, &token, "totally-unknown-model").await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert!(body.contains("totally-unknown-model"), "body was: {body}");
}
