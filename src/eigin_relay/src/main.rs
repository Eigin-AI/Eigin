use std::collections::HashMap;
use std::env;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use axum::Router;
use axum::middleware;
use axum::routing::{get, post};
use tower_http::trace::TraceLayer;
use tracing_subscriber::EnvFilter;

use eigin_relay::credits::apple::{AppStoreVerifier, load_root_certs};
use eigin_relay::credits::grant::{Ed25519GrantVerifier, GrantVerifier, RejectingGrantVerifier};
use eigin_relay::credits::token::parse_encryption_key;
use eigin_relay::credits::{CreditLedger, InMemoryLedger, PostgresLedger};
use eigin_relay::inference::catalog::{ModelConfig, ModelsConfig, ProductsConfig};
use eigin_relay::inference::upstream::{ReqwestUpstreamClient, UpstreamClient};
use eigin_relay::{
    AppState, Pool, PoolConfig, RateLimiter, create_client, health, require_eigin_key, search,
};

// ── Config structs ────────────────────────────────────────────────────────────

struct SearchConfig {
    client: Arc<dyn eigin_relay::search::SearchClient>,
    mojeek_api_key: String,
    eigin_relay_key: String,
    pool: Pool,
    rate_limiter: RateLimiter,
}

struct CreditsConfig {
    ledger: Arc<dyn CreditLedger>,
    token_encryption_key: [u8; 32],
    apple_verifier: Arc<dyn eigin_relay::credits::apple::AppleVerifier>,
    grant_verifier: Arc<dyn eigin_relay::credits::grant::GrantVerifier>,
    product_credits: HashMap<String, i64>,
}

struct InferenceConfig {
    upstream_client: Arc<dyn UpstreamClient>,
    upstream_api_key: Option<String>,
    model_rates: HashMap<String, ModelConfig>,
    admit_floor_millicredits: i64,
    token_rate_limiter: RateLimiter<uuid::Uuid>,
}

// ── Entry point ───────────────────────────────────────────────────────────────

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::from_default_env().add_directive("eigin_relay=info".parse().unwrap()),
        )
        .init();

    let port: u16 = env::var("PORT")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(8080);

    let search = configure_search().await;
    let credits = configure_credits().await;
    let inference = configure_inference();

    let state = Arc::new(AppState {
        search_client: search.client,
        mojeek_api_key: search.mojeek_api_key,
        eigin_relay_key: search.eigin_relay_key,
        pool: search.pool,
        ip_rate_limiter: search.rate_limiter,
        ledger: credits.ledger,
        apple_verifier: credits.apple_verifier,
        grant_verifier: credits.grant_verifier,
        product_credits: credits.product_credits,
        token_encryption_key: credits.token_encryption_key,
        upstream_client: inference.upstream_client,
        upstream_api_key: inference.upstream_api_key,
        model_rates: inference.model_rates,
        admit_floor_millicredits: inference.admit_floor_millicredits,
        token_rate_limiter: inference.token_rate_limiter,
    });

    let app = build_router(state);

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    tracing::info!(%addr, "starting eigin-relay");

    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .await
    .unwrap();
}

// ── Configuration helpers ─────────────────────────────────────────────────────

async fn configure_search() -> SearchConfig {
    let mojeek_api_key = env::var("MOJEEK_API_KEY").expect("MOJEEK_API_KEY must be set");
    let eigin_relay_key = env::var("EIGIN_RELAY_KEY").expect("EIGIN_RELAY_KEY must be set");
    let search_api_url =
        env::var("SEARCH_API_URL").unwrap_or_else(|_| "https://api.mojeek.com".to_string());
    let rate_limit_requests: u32 = env::var("RATE_LIMIT_REQUESTS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(10);
    let rate_limit_window_secs: u64 = env::var("RATE_LIMIT_WINDOW_SECONDS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(60);
    let pool_size: u64 = env::var("MONTHLY_POOL_SIZE")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(5000);

    let client = create_client(reqwest::Client::new(), &search_api_url);
    let pool_config = PoolConfig::from_env().expect("failed to load pool configuration");
    let pool = Pool::load(pool_size, pool_config).await;
    let rate_limiter = RateLimiter::new(
        rate_limit_requests,
        Duration::from_secs(rate_limit_window_secs),
    );

    SearchConfig {
        client,
        mojeek_api_key,
        eigin_relay_key,
        pool,
        rate_limiter,
    }
}

async fn configure_credits() -> CreditsConfig {
    let ledger: Arc<dyn CreditLedger> = match env::var("DATABASE_URL") {
        Ok(url) => {
            tracing::info!("using PostgresLedger");
            Arc::new(
                PostgresLedger::new(&url)
                    .await
                    .expect("failed to connect to database"),
            )
        }
        Err(_) => {
            tracing::warn!("DATABASE_URL not set — using InMemoryLedger (dev only)");
            Arc::new(InMemoryLedger::default())
        }
    };

    // Treat an empty value as unset: `just run relay` exports the var unconditionally, so
    // a missing .env entry arrives as "" rather than absent. A non-empty but malformed key
    // is still a hard error.
    let token_encryption_key = env::var("TOKEN_ENCRYPTION_KEY")
        .ok()
        .filter(|v| !v.trim().is_empty())
        .map(|v| parse_encryption_key(&v).expect("invalid TOKEN_ENCRYPTION_KEY"))
        .unwrap_or_else(|| {
            tracing::warn!("TOKEN_ENCRYPTION_KEY not set — using insecure dev key");
            [0u8; 32]
        });

    let apple_verifier = configure_apple_verifier();
    let grant_verifier = configure_grant_verifier();

    let products_config_path =
        env::var("PRODUCTS_CONFIG_PATH").unwrap_or_else(|_| "config/products.toml".into());
    let product_credits: HashMap<String, i64> = ProductsConfig::load(&products_config_path)
        .map(|c| c.products.into_iter().map(|(k, v)| (k, v as i64)).collect())
        .unwrap_or_else(|e| {
            tracing::warn!("{e} — no IAP products configured");
            HashMap::new()
        });

    CreditsConfig {
        ledger,
        token_encryption_key,
        apple_verifier,
        grant_verifier,
        product_credits,
    }
}

fn configure_apple_verifier() -> Arc<dyn eigin_relay::credits::apple::AppleVerifier> {
    let apple_bundle_id = env::var("APPLE_BUNDLE_ID").unwrap_or_default();
    let apple_environment = env::var("APPLE_ENVIRONMENT").unwrap_or_else(|_| "Sandbox".into());
    let apple_app_apple_id: Option<i64> = env::var("APPLE_APP_APPLE_ID")
        .ok()
        .and_then(|v| v.parse().ok());
    let root_certs = load_root_certs("config/apple");

    if apple_bundle_id.is_empty() {
        tracing::warn!(
            "APPLE_BUNDLE_ID not set — Apple verification will fail for real transactions"
        );
        Arc::new(
            AppStoreVerifier::new(
                root_certs,
                "dev.placeholder".into(),
                None,
                &apple_environment,
            )
            .expect("failed to create placeholder Apple verifier"),
        )
    } else {
        Arc::new(
            AppStoreVerifier::new(
                root_certs,
                apple_bundle_id,
                apple_app_apple_id,
                &apple_environment,
            )
            .expect("failed to create Apple verifier"),
        )
    }
}

fn configure_grant_verifier() -> Arc<dyn GrantVerifier> {
    let issuer = env::var("GRANT_ISSUER").unwrap_or_else(|_| "eigin".into());

    // The public key is environment-specific, so it is injected at runtime (Secret Manager
    // in production, the local per-env PEM in dev) rather than baked into the image. A
    // missing key disables grant redemption.
    match env::var("GRANT_PUBLIC_KEY") {
        Ok(pem) if !pem.trim().is_empty() => Arc::new(
            Ed25519GrantVerifier::from_public_pem(&pem, &issuer).expect("invalid GRANT_PUBLIC_KEY"),
        ),
        _ => {
            tracing::warn!("GRANT_PUBLIC_KEY not set — grant redemption disabled");
            Arc::new(RejectingGrantVerifier)
        }
    }
}

fn configure_inference() -> InferenceConfig {
    let upstream_api_url = env::var("UPSTREAM_API_URL").ok();
    let upstream_api_key = env::var("UPSTREAM_API_KEY").ok();

    if upstream_api_url.is_none() {
        tracing::warn!("UPSTREAM_API_URL not set — inference routes will return 503");
    }
    if upstream_api_key.is_none() {
        tracing::warn!("UPSTREAM_API_KEY not set — inference routes will return 503");
    }

    let admit_floor_credits: i64 = env::var("ADMIT_FLOOR_CREDITS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(50);
    let admit_floor_millicredits = admit_floor_credits * 1000;

    let token_rate_limit_requests: u32 = env::var("TOKEN_RATE_LIMIT_REQUESTS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(20);
    let token_rate_limit_window_secs: u64 = env::var("TOKEN_RATE_LIMIT_WINDOW_SECONDS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(60);

    let models_config_path =
        env::var("MODELS_CONFIG_PATH").unwrap_or_else(|_| "config/models.toml".into());
    let model_rates = ModelsConfig::load(&models_config_path)
        .map(|c| c.into_rate_map())
        .unwrap_or_else(|e| {
            tracing::warn!("{e} — no models available");
            HashMap::new()
        });

    let upstream_client = Arc::new(ReqwestUpstreamClient::new(
        reqwest::Client::new(),
        upstream_api_url.unwrap_or_default(),
    ));

    let token_rate_limiter = RateLimiter::new(
        token_rate_limit_requests,
        Duration::from_secs(token_rate_limit_window_secs),
    );

    InferenceConfig {
        upstream_client,
        upstream_api_key,
        model_rates,
        admit_floor_millicredits,
        token_rate_limiter,
    }
}

// ── Router ────────────────────────────────────────────────────────────────────

fn build_router(state: Arc<AppState>) -> Router {
    // Routes gated by Eigin Relay key.
    let routes_with_eigin_key = Router::new()
        .route("/search", get(search::handle)) // legacy — keep until app migrates to /v1/search
        .route("/v1/search", get(search::handle))
        .route(
            "/v1/credits/redeem",
            post(eigin_relay::credits::redeem::handle),
        )
        .route(
            "/v1/credits/products",
            get(eigin_relay::credits::products::handle),
        )
        // The model catalog is static and free to read, so it needs no wallet — only the relay key.
        .route(
            "/v1/models",
            get(eigin_relay::inference::catalog::handle_list),
        )
        .layer(middleware::from_fn_with_state(
            state.clone(),
            require_eigin_key,
        ));

    // Routes gated by Eigin Relay key + credit token.
    let routes_with_bearer = Router::new()
        .route(
            "/v1/credits/balance",
            get(eigin_relay::credits::balance::handle),
        )
        .route(
            "/v1/chat/completions",
            post(eigin_relay::inference::handler::handle),
        )
        .layer(middleware::from_fn_with_state(
            state.clone(),
            require_eigin_key,
        ));

    Router::new()
        // Unauthenticated routes like health, docs and webhooks.
        .route("/health", get(health))
        .route("/docs", get(eigin_relay::docs::handler))
        .route(
            "/webhooks/apple/appstore",
            post(eigin_relay::credits::apple::webhook::handle),
        )
        .merge(routes_with_eigin_key)
        .merge(routes_with_bearer)
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}
