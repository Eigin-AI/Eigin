use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use axum::body::to_bytes;
use axum::extract::ConnectInfo;
use axum::http::{Request, StatusCode};
use tower::util::ServiceExt;

mod mock_client {
    use std::sync::{Arc, Mutex};

    use async_trait::async_trait;
    use eigin_relay::{SearchClient, SearchOptions};

    pub struct MockClient {
        response: Vec<u8>,
        should_error: bool,
        error_message: String,
        /// Records the options passed to the most recent `search` call, so tests
        /// can assert on how the handler translated client params.
        captured_options: Arc<Mutex<Option<SearchOptions>>>,
    }

    impl MockClient {
        pub fn new(response: Vec<u8>) -> Self {
            Self {
                response,
                should_error: false,
                error_message: String::new(),
                captured_options: Arc::new(Mutex::new(None)),
            }
        }

        pub fn with_error(message: impl Into<String>) -> Self {
            Self {
                response: Vec::new(),
                should_error: true,
                error_message: message.into(),
                captured_options: Arc::new(Mutex::new(None)),
            }
        }

        /// Returns a handle that can be inspected for the options passed to the
        /// most recent `search` call, alongside the client itself.
        pub fn spy(response: Vec<u8>) -> (Self, Arc<Mutex<Option<SearchOptions>>>) {
            let captured_options = Arc::new(Mutex::new(None));
            let client = Self {
                response,
                should_error: false,
                error_message: String::new(),
                captured_options: captured_options.clone(),
            };
            (client, captured_options)
        }
    }

    #[async_trait]
    impl SearchClient for MockClient {
        async fn search(
            &self,
            _api_key: &str,
            _query: &str,
            options: &SearchOptions,
        ) -> Result<Vec<u8>, eigin_relay::AppError> {
            *self.captured_options.lock().unwrap() = Some(options.clone());
            if self.should_error {
                return Err(eigin_relay::AppError::Upstream(self.error_message.clone()));
            }
            Ok(self.response.clone())
        }
    }
}

mod fakes;
use fakes::apple::FakeVerifier;
use fakes::grant::FakeGrantVerifier;

use mock_client::MockClient;

async fn test_state(
    pool_max: u64,
    client: impl eigin_relay::SearchClient + 'static,
) -> Arc<eigin_relay::AppState> {
    test_state_with_keys(pool_max, client, vec!["test-relay-key".to_string()]).await
}

async fn test_state_with_keys(
    pool_max: u64,
    client: impl eigin_relay::SearchClient + 'static,
    eigin_relay_keys: Vec<String>,
) -> Arc<eigin_relay::AppState> {
    use eigin_relay::credits::InMemoryLedger;
    use eigin_relay::quota::InMemoryQuota;

    Arc::new(eigin_relay::AppState {
        search_client: Arc::new(client),
        mojeek_api_key: "test-api-key".to_string(),
        eigin_relay_keys,
        ip_rate_limiter: eigin_relay::RateLimiter::new(10, Duration::from_secs(60)),
        trusted_proxy_hops: 1,
        webhook_rate_limiter: eigin_relay::RateLimiter::new(10, Duration::from_secs(60)),
        search_pool_max: pool_max,
        search_window: Duration::from_secs(30 * 24 * 60 * 60),
        quota: Arc::new(InMemoryQuota::default()),
        ledger: Arc::new(InMemoryLedger::default()),
        apple_verifier: Arc::new(FakeVerifier::failing()),
        grant_verifier: Arc::new(FakeGrantVerifier::failing()),
        product_credits: HashMap::new(),
        token_encryption_key: [0u8; 32],
        token_encryption_key_secondary: None,
        sandbox_budget_credits: 25_000,
        sandbox_budget_window: Duration::from_secs(30 * 24 * 60 * 60),
        provider_clients: HashMap::new(),
        provider_keys: HashMap::new(),
        canonical_models: HashMap::new(),
        alias_map: HashMap::new(),
        admit_floor_millicredits: 50_000,
        token_rate_limiter: eigin_relay::RateLimiter::new(20, Duration::from_secs(60)),
    })
}

// Exercise the real, fully-layered router so tests cover the middleware stack
// (client-IP resolution + blanket per-IP limiting) exactly as deployed.
fn router(state: Arc<eigin_relay::AppState>) -> axum::Router {
    eigin_relay::build_router(state)
}

async fn call(app: &axum::Router, uri: &str, key: Option<&str>) -> axum::response::Response {
    let connect_info = ConnectInfo(std::net::SocketAddr::from(([127, 0, 0, 1], 8080)));

    let mut req = Request::builder()
        .uri(uri)
        .extension(connect_info)
        .body(axum::body::Body::empty())
        .unwrap();

    if let Some(k) = key {
        req.headers_mut().insert(
            axum::http::header::HeaderName::from_static("x-eigin-key"),
            axum::http::HeaderValue::from_str(k).unwrap(),
        );
    }

    app.clone().oneshot(req).await.unwrap()
}

// --- Search tests (unchanged behaviour) ---

#[tokio::test]
async fn health_returns_ok() {
    let mock = MockClient::new(b"{\"response\":{\"results\":[]}}".to_vec());
    let state = test_state(1000, mock).await;
    let app = router(state);

    let response = call(&app, "/health", None).await;

    assert_eq!(response.status(), StatusCode::OK);
    let body = to_bytes(response.into_body(), 1024).await.unwrap();
    assert_eq!(&body[..], b"{\"status\":\"ok\"}");
}

#[tokio::test]
async fn search_without_key_returns_401() {
    let mock = MockClient::new(b"{\"response\":{\"results\":[]}}".to_vec());
    let state = test_state(1000, mock).await;
    let app = router(state);

    let response = call(&app, "/v1/search?q=test", None).await;

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    let body = to_bytes(response.into_body(), 1024).await.unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    // Error is now OpenAI-compatible: { "error": { "message": "..." } }
    assert_eq!(json["error"]["message"], "invalid or missing API key");
}

#[tokio::test]
async fn search_with_wrong_key_returns_401() {
    let mock = MockClient::new(b"{\"response\":{\"results\":[]}}".to_vec());
    let state = test_state(1000, mock).await;
    let app = router(state);

    let response = call(&app, "/v1/search?q=test", Some("wrong-key")).await;

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// When two keys are configured (primary + secondary during a rotation), either one
// authenticates and an unconfigured key is still rejected. This is the property
// that lets a key be rotated without breaking already-shipped app builds.
#[tokio::test]
async fn search_accepts_either_configured_key_and_rejects_others() {
    let make = || async {
        router(
            test_state_with_keys(
                1000,
                MockClient::new(b"{\"response\":{\"results\":[]}}".to_vec()),
                vec!["primary-key".to_string(), "secondary-key".to_string()],
            )
            .await,
        )
    };

    assert_eq!(
        call(&make().await, "/v1/search?q=test", Some("primary-key"))
            .await
            .status(),
        StatusCode::OK
    );
    assert_eq!(
        call(&make().await, "/v1/search?q=test", Some("secondary-key"))
            .await
            .status(),
        StatusCode::OK
    );
    assert_eq!(
        call(&make().await, "/v1/search?q=test", Some("retired-key"))
            .await
            .status(),
        StatusCode::UNAUTHORIZED
    );
}

#[tokio::test]
async fn search_without_query_returns_400() {
    let mock = MockClient::new(b"{\"response\":{\"results\":[]}}".to_vec());
    let state = test_state(1000, mock).await;
    let app = router(state);

    let response = call(&app, "/v1/search", Some("test-relay-key")).await;

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    let body = to_bytes(response.into_body(), 1024).await.unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(json["error"]["message"], "missing 'q' parameter");
}

#[tokio::test]
async fn search_with_empty_query_returns_400() {
    let mock = MockClient::new(b"{\"response\":{\"results\":[]}}".to_vec());
    let state = test_state(1000, mock).await;
    let app = router(state);

    let response = call(&app, "/v1/search?q=%20", Some("test-relay-key")).await;

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn search_proxies_upstream_response() {
    let mock_response = serde_json::json!({
        "response": {
            "title": "Test Results",
            "results": [
                {"title": "Result 1", "url": "https://example.com/1", "desc": "About result 1"},
                {"title": "Result 2", "url": "https://example.com/2", "desc": "About result 2"}
            ]
        }
    });

    let mock = MockClient::new(mock_response.to_string().into_bytes());
    let state = test_state(1000, mock).await;
    let app = router(state);

    let response = call(&app, "/v1/search?q=rust", Some("test-relay-key")).await;

    assert_eq!(response.status(), StatusCode::OK);
    let body = to_bytes(response.into_body(), 4096).await.unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    // The raw Mojeek envelope (head, cats, etc.) is stripped — only a small,
    // stable result shape is returned to clients.
    let results = json["results"].as_array().unwrap();
    assert_eq!(results.len(), 2);
    assert_eq!(results[0]["title"], "Result 1");
    assert_eq!(results[0]["url"], "https://example.com/1");
    assert_eq!(results[0]["desc"], "About result 1");
}

#[tokio::test]
async fn search_forwards_recognised_focus_and_region() {
    let (mock, captured) = MockClient::spy(b"{\"response\":{\"results\":[]}}".to_vec());
    let state = test_state(1000, mock).await;
    let app = router(state);

    let response = call(
        &app,
        "/v1/search?q=pandekager&region=dk&focus=recipes",
        Some("test-relay-key"),
    )
    .await;

    assert_eq!(response.status(), StatusCode::OK);
    let options = captured.lock().unwrap().clone().expect("search was called");
    assert_eq!(options.region.as_deref(), Some("DK"));
    assert_eq!(options.focus, Some(eigin_relay::SearchFocus::Recipes));
}

#[tokio::test]
async fn search_drops_unrecognised_focus_and_malformed_region() {
    let (mock, captured) = MockClient::spy(b"{\"response\":{\"results\":[]}}".to_vec());
    let state = test_state(1000, mock).await;
    let app = router(state);

    let response = call(
        &app,
        "/v1/search?q=test&region=denmark&focus=bogus",
        Some("test-relay-key"),
    )
    .await;

    assert_eq!(response.status(), StatusCode::OK);
    let options = captured.lock().unwrap().clone().expect("search was called");
    assert_eq!(options.region, None);
    assert_eq!(options.focus, None);
}

#[tokio::test]
async fn search_upstream_error_returns_502() {
    let mock = MockClient::with_error("connection refused");
    let state = test_state(1000, mock).await;
    let app = router(state);

    let response = call(&app, "/v1/search?q=test", Some("test-relay-key")).await;

    assert_eq!(response.status(), StatusCode::BAD_GATEWAY);
    let body = to_bytes(response.into_body(), 1024).await.unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    // Opaque body: the underlying error detail must not reach the client.
    assert_eq!(json["error"]["message"], "upstream service error");
    assert!(
        !json["error"]["message"]
            .as_str()
            .unwrap()
            .contains("connection refused")
    );
}

// --- Blanket per-IP layer + client-IP derivation ---

async fn test_state_with_ip_limit(
    ip_max: u32,
    client: impl eigin_relay::SearchClient + 'static,
) -> Arc<eigin_relay::AppState> {
    use eigin_relay::credits::InMemoryLedger;
    use eigin_relay::quota::InMemoryQuota;

    Arc::new(eigin_relay::AppState {
        search_client: Arc::new(client),
        mojeek_api_key: "test-api-key".to_string(),
        eigin_relay_keys: vec!["test-relay-key".to_string()],
        ip_rate_limiter: eigin_relay::RateLimiter::new(ip_max, Duration::from_secs(60)),
        trusted_proxy_hops: 1,
        webhook_rate_limiter: eigin_relay::RateLimiter::new(100, Duration::from_secs(60)),
        search_pool_max: 1_000_000,
        search_window: Duration::from_secs(30 * 24 * 60 * 60),
        quota: Arc::new(InMemoryQuota::default()),
        ledger: Arc::new(InMemoryLedger::default()),
        apple_verifier: Arc::new(FakeVerifier::failing()),
        grant_verifier: Arc::new(FakeGrantVerifier::failing()),
        product_credits: HashMap::new(),
        token_encryption_key: [0u8; 32],
        token_encryption_key_secondary: None,
        sandbox_budget_credits: 25_000,
        sandbox_budget_window: Duration::from_secs(30 * 24 * 60 * 60),
        provider_clients: HashMap::new(),
        provider_keys: HashMap::new(),
        canonical_models: HashMap::new(),
        alias_map: HashMap::new(),
        admit_floor_millicredits: 50_000,
        token_rate_limiter: eigin_relay::RateLimiter::new(100, Duration::from_secs(60)),
    })
}

/// Like `call`, but sets an `X-Forwarded-For` header so the layer derives the
/// client IP from it rather than the (fixed) peer address.
async fn call_with_xff(
    app: &axum::Router,
    uri: &str,
    key: Option<&str>,
    xff: &str,
) -> axum::response::Response {
    let connect_info = ConnectInfo(std::net::SocketAddr::from(([10, 0, 0, 1], 8080)));
    let mut req = Request::builder()
        .uri(uri)
        .extension(connect_info)
        .header("x-forwarded-for", xff)
        .body(axum::body::Body::empty())
        .unwrap();
    if let Some(k) = key {
        req.headers_mut().insert(
            axum::http::header::HeaderName::from_static("x-eigin-key"),
            axum::http::HeaderValue::from_str(k).unwrap(),
        );
    }
    app.clone().oneshot(req).await.unwrap()
}

// The blanket layer caps a route that had no in-handler limiter (`/v1/models`),
// proving new routes are covered by default.
#[tokio::test]
async fn blanket_layer_caps_previously_uncapped_route() {
    let mock = MockClient::new(b"{\"response\":{\"results\":[]}}".to_vec());
    let state = test_state_with_ip_limit(3, mock).await;
    let app = router(state);

    for _ in 0..3 {
        let response = call(&app, "/v1/models", Some("test-relay-key")).await;
        assert_eq!(response.status(), StatusCode::OK);
    }
    let response = call(&app, "/v1/models", Some("test-relay-key")).await;
    assert_eq!(response.status(), StatusCode::TOO_MANY_REQUESTS);
}

// The limiter keys on the forwarded client IP, not the shared proxy peer:
// distinct clients get independent buckets, and a spoofed leftmost entry can't
// win a fresh bucket (the trusted rightmost hop decides the key).
#[tokio::test]
async fn rate_limit_keys_on_forwarded_client_not_proxy() {
    let mock = MockClient::new(b"{\"response\":{\"results\":[]}}".to_vec());
    let state = test_state_with_ip_limit(2, mock).await;
    let app = router(state);

    let key = Some("test-relay-key");

    // Client A (1.1.1.1) uses its two allowed requests, then is capped.
    assert_eq!(
        call_with_xff(&app, "/v1/models", key, "1.1.1.1")
            .await
            .status(),
        StatusCode::OK
    );
    assert_eq!(
        call_with_xff(&app, "/v1/models", key, "1.1.1.1")
            .await
            .status(),
        StatusCode::OK
    );
    assert_eq!(
        call_with_xff(&app, "/v1/models", key, "1.1.1.1")
            .await
            .status(),
        StatusCode::TOO_MANY_REQUESTS
    );

    // Client B (2.2.2.2) has its own bucket and is unaffected.
    assert_eq!(
        call_with_xff(&app, "/v1/models", key, "2.2.2.2")
            .await
            .status(),
        StatusCode::OK
    );

    // A spoofed leftmost entry is ignored; this keys on 1.1.1.1 (already capped).
    assert_eq!(
        call_with_xff(&app, "/v1/models", key, "9.9.9.9, 1.1.1.1")
            .await
            .status(),
        StatusCode::TOO_MANY_REQUESTS
    );
}

// `/health` is deliberately excluded from the blanket limiter (Scaleway probes it).
#[tokio::test]
async fn health_is_never_rate_limited() {
    let mock = MockClient::new(b"{\"response\":{\"results\":[]}}".to_vec());
    let state = test_state_with_ip_limit(2, mock).await;
    let app = router(state);

    for _ in 0..5 {
        assert_eq!(call(&app, "/health", None).await.status(), StatusCode::OK);
    }
}

#[tokio::test]
async fn search_rate_limited_after_10_requests() {
    let mock = MockClient::new(b"{\"response\":{\"results\":[]}}".to_vec());
    let state = test_state(1000, mock).await;
    let app = router(state);

    for i in 0..11 {
        let response = call(
            &app,
            &format!("/v1/search?q=test{i}"),
            Some("test-relay-key"),
        )
        .await;

        if i >= 10 {
            assert_eq!(response.status(), StatusCode::TOO_MANY_REQUESTS);
            let body = to_bytes(response.into_body(), 1024).await.unwrap();
            let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
            assert_eq!(json["error"]["message"], "rate limited — try again shortly");
        }
    }
}

#[tokio::test]
async fn search_pool_exhausts_after_quota_reached() {
    // Pool of 2 searches; the IP limiter is high enough not to interfere.
    let mock = MockClient::new(b"{\"response\":{\"results\":[]}}".to_vec());
    let state = test_state(2, mock).await;
    let app = router(state);

    for _ in 0..2 {
        let response = call(&app, "/v1/search?q=test", Some("test-relay-key")).await;
        assert_eq!(response.status(), StatusCode::OK);
    }

    // Third search exceeds the community pool quota.
    let response = call(&app, "/v1/search?q=test", Some("test-relay-key")).await;
    assert_eq!(response.status(), StatusCode::TOO_MANY_REQUESTS);
    let body = to_bytes(response.into_body(), 1024).await.unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(json["error"]["message"], "monthly search quota exhausted");
}
