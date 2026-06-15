use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use axum::Router;
use axum::body::to_bytes;
use axum::extract::ConnectInfo;
use axum::http::{Request, StatusCode};
use axum::middleware;
use axum::routing::{get, post};
use tower::util::ServiceExt;

mod mock_client {
    use async_trait::async_trait;
    use eigin_relay::SearchClient;

    pub struct MockClient {
        response: Vec<u8>,
        should_error: bool,
        error_message: String,
    }

    impl MockClient {
        pub fn new(response: Vec<u8>) -> Self {
            Self {
                response,
                should_error: false,
                error_message: String::new(),
            }
        }

        pub fn with_error(message: impl Into<String>) -> Self {
            Self {
                response: Vec::new(),
                should_error: true,
                error_message: message.into(),
            }
        }
    }

    #[async_trait]
    impl SearchClient for MockClient {
        async fn search(
            &self,
            _api_key: &str,
            _query: &str,
        ) -> Result<Vec<u8>, eigin_relay::AppError> {
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
use fakes::upstream::NoopUpstream;

use mock_client::MockClient;

async fn test_state(
    pool_max: u64,
    client: impl eigin_relay::SearchClient + 'static,
) -> Arc<eigin_relay::AppState> {
    use eigin_relay::credits::InMemoryLedger;

    Arc::new(eigin_relay::AppState {
        search_client: Arc::new(client),
        mojeek_api_key: "test-api-key".to_string(),
        eigin_relay_key: "test-relay-key".to_string(),
        pool: eigin_relay::Pool::load(pool_max, eigin_relay::PoolConfig::InMemory).await,
        ip_rate_limiter: eigin_relay::RateLimiter::new(10, Duration::from_secs(60)),
        ledger: Arc::new(InMemoryLedger::default()),
        apple_verifier: Arc::new(FakeVerifier::failing()),
        grant_verifier: Arc::new(FakeGrantVerifier::failing()),
        product_credits: HashMap::new(),
        token_encryption_key: [0u8; 32],
        upstream_client: Arc::new(NoopUpstream),
        upstream_api_key: None,
        model_rates: HashMap::new(),
        admit_floor_millicredits: 50_000,
        token_rate_limiter: eigin_relay::RateLimiter::new(20, Duration::from_secs(60)),
    })
}

fn router(state: Arc<eigin_relay::AppState>) -> axum::Router {
    let authed = Router::new()
        .route("/search", get(eigin_relay::search::handle))
        .route("/v1/search", get(eigin_relay::search::handle))
        .route(
            "/v1/credits/redeem",
            post(eigin_relay::credits::redeem::handle),
        )
        .layer(middleware::from_fn_with_state(
            state.clone(),
            eigin_relay::require_eigin_key,
        ));

    Router::new()
        .route("/health", get(eigin_relay::health))
        .route(
            "/webhooks/apple/appstore",
            post(eigin_relay::credits::apple::webhook::handle),
        )
        .merge(authed)
        .with_state(state)
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
    let mock = MockClient::new(b"{}".to_vec());
    let state = test_state(1000, mock).await;
    let app = router(state);

    let response = call(&app, "/health", None).await;

    assert_eq!(response.status(), StatusCode::OK);
    let body = to_bytes(response.into_body(), 1024).await.unwrap();
    assert_eq!(&body[..], b"{\"status\":\"ok\"}");
}

#[tokio::test]
async fn search_without_key_returns_401() {
    let mock = MockClient::new(b"{}".to_vec());
    let state = test_state(1000, mock).await;
    let app = router(state);

    let response = call(&app, "/search?q=test", None).await;

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    let body = to_bytes(response.into_body(), 1024).await.unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    // Error is now OpenAI-compatible: { "error": { "message": "..." } }
    assert_eq!(json["error"]["message"], "invalid or missing API key");
}

#[tokio::test]
async fn search_with_wrong_key_returns_401() {
    let mock = MockClient::new(b"{}".to_vec());
    let state = test_state(1000, mock).await;
    let app = router(state);

    let response = call(&app, "/search?q=test", Some("wrong-key")).await;

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn search_without_query_returns_400() {
    let mock = MockClient::new(b"{}".to_vec());
    let state = test_state(1000, mock).await;
    let app = router(state);

    let response = call(&app, "/search", Some("test-relay-key")).await;

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    let body = to_bytes(response.into_body(), 1024).await.unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(json["error"]["message"], "missing 'q' parameter");
}

#[tokio::test]
async fn search_with_empty_query_returns_400() {
    let mock = MockClient::new(b"{}".to_vec());
    let state = test_state(1000, mock).await;
    let app = router(state);

    let response = call(&app, "/search?q=%20", Some("test-relay-key")).await;

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn search_proxies_upstream_response() {
    let mock_response = serde_json::json!({
        "response": {
            "title": "Test Results",
            "results": [
                {"title": "Result 1", "url": "https://example.com/1"},
                {"title": "Result 2", "url": "https://example.com/2"}
            ]
        }
    });

    let mock = MockClient::new(mock_response.to_string().into_bytes());
    let state = test_state(1000, mock).await;
    let app = router(state);

    let response = call(&app, "/search?q=rust", Some("test-relay-key")).await;

    assert_eq!(response.status(), StatusCode::OK);
    let body = to_bytes(response.into_body(), 4096).await.unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(json["response"]["results"].as_array().unwrap().len(), 2);
}

#[tokio::test]
async fn search_upstream_error_returns_502() {
    let mock = MockClient::with_error("connection refused");
    let state = test_state(1000, mock).await;
    let app = router(state);

    let response = call(&app, "/search?q=test", Some("test-relay-key")).await;

    assert_eq!(response.status(), StatusCode::BAD_GATEWAY);
    let body = to_bytes(response.into_body(), 1024).await.unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert!(
        json["error"]["message"]
            .as_str()
            .unwrap()
            .contains("upstream error")
    );
}

#[tokio::test]
async fn search_rate_limited_after_10_requests() {
    let mock = MockClient::new(b"{}".to_vec());
    let state = test_state(1000, mock).await;
    let app = router(state);

    for i in 0..11 {
        let response = call(&app, &format!("/search?q=test{i}"), Some("test-relay-key")).await;

        if i >= 10 {
            assert_eq!(response.status(), StatusCode::TOO_MANY_REQUESTS);
            let body = to_bytes(response.into_body(), 1024).await.unwrap();
            let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
            assert_eq!(json["error"]["message"], "rate limited — try again shortly");
        }
    }
}

#[tokio::test]
async fn search_with_file_backend_pool() {
    let tmp = tempfile::TempDir::new().unwrap();
    let path = tmp.path().join("pool.json");
    let pool = eigin_relay::Pool::load(100, eigin_relay::PoolConfig::LocalFile(path.clone())).await;
    assert_eq!(pool.remaining(), 100);

    for _ in 0..5 {
        pool.try_consume().await.unwrap();
    }
    assert_eq!(pool.remaining(), 95);
}
