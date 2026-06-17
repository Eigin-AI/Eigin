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

use eigin_relay::credits::apple::{AppStoreVerifier, MultiEnvironmentVerifier, load_root_certs};
use eigin_relay::credits::grant::{Ed25519GrantVerifier, GrantVerifier, RejectingGrantVerifier};
use eigin_relay::credits::postgres::connect_and_migrate;
use eigin_relay::credits::token::parse_encryption_key;
use eigin_relay::credits::{CreditLedger, InMemoryLedger, PostgresLedger};
use eigin_relay::inference::catalog::{ModelConfig, ModelsConfig, ProductsConfig};
use eigin_relay::inference::upstream::{ReqwestUpstreamClient, UpstreamClient};
use eigin_relay::quota::{InMemoryQuota, PostgresQuota, Quota};
use eigin_relay::{AppState, RateLimiter, create_client, health, require_eigin_key, search};
use sqlx::PgPool;

// ── Config structs ────────────────────────────────────────────────────────────

struct SearchConfig {
    client: Arc<dyn eigin_relay::search::SearchClient>,
    mojeek_api_key: String,
    pool_max: u64,
    window: Duration,
    rate_limiter: RateLimiter,
}

struct CreditsConfig {
    ledger: Arc<dyn CreditLedger>,
    token_encryption_key: [u8; 32],
    apple_verifier: Arc<dyn eigin_relay::credits::apple::AppleVerifier>,
    grant_verifier: Arc<dyn eigin_relay::credits::grant::GrantVerifier>,
    product_credits: HashMap<String, i64>,
    sandbox_budget_credits: u64,
    sandbox_budget_window: Duration,
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

    // One database pool, shared by the ledger and the quota (or none in dev).
    let db_pool = configure_database().await;

    let eigin_relay_keys = configure_relay_keys();
    let search = configure_search().await;
    let credits = configure_credits(db_pool.clone()).await;
    let quota = configure_quota(db_pool.clone());
    let inference = configure_inference();

    let state = Arc::new(AppState {
        search_client: search.client,
        mojeek_api_key: search.mojeek_api_key,
        eigin_relay_keys,
        ip_rate_limiter: search.rate_limiter,
        search_pool_max: search.pool_max,
        search_window: search.window,
        quota,
        ledger: credits.ledger,
        apple_verifier: credits.apple_verifier,
        grant_verifier: credits.grant_verifier,
        product_credits: credits.product_credits,
        token_encryption_key: credits.token_encryption_key,
        sandbox_budget_credits: credits.sandbox_budget_credits,
        sandbox_budget_window: credits.sandbox_budget_window,
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

/// The keys this relay accepts on the `x-eigin-key` gate (all routes, not just search).
///
/// A required generated primary, plus an optional supplied secondary that holds the
/// previous key during a rotation so already-shipped app builds keep working.
fn configure_relay_keys() -> Vec<String> {
    let primary = env::var("EIGIN_RELAY_PRIMARY_KEY").expect("EIGIN_RELAY_PRIMARY_KEY must be set");
    std::iter::once(primary)
        .chain(
            env::var("EIGIN_RELAY_SECONDARY_KEY")
                .ok()
                .filter(|v| !v.trim().is_empty()),
        )
        .collect()
}

async fn configure_search() -> SearchConfig {
    let mojeek_api_key = env::var("MOJEEK_API_KEY").expect("MOJEEK_API_KEY must be set");
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
    let window_days: u64 = env::var("SEARCH_POOL_WINDOW_DAYS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(30);

    let client = create_client(reqwest::Client::new(), &search_api_url);
    let rate_limiter = RateLimiter::new(
        rate_limit_requests,
        Duration::from_secs(rate_limit_window_secs),
    );

    SearchConfig {
        client,
        mojeek_api_key,
        pool_max: pool_size,
        window: Duration::from_secs(window_days * 24 * 60 * 60),
        rate_limiter,
    }
}

/// Build the shared database pool (running migrations) if `DATABASE_URL` is set.
/// Returns `None` in dev, where in-memory ledger and quota are used instead.
async fn configure_database() -> Option<PgPool> {
    match env::var("DATABASE_URL") {
        Ok(url) if !url.trim().is_empty() => Some(
            connect_and_migrate(&url)
                .await
                .expect("failed to connect to database"),
        ),
        _ => {
            tracing::warn!("DATABASE_URL not set — using in-memory ledger and quota (dev only)");
            None
        }
    }
}

/// Build the rolling-window quota over the shared pool, or in-memory in dev.
fn configure_quota(db_pool: Option<PgPool>) -> Arc<dyn Quota> {
    match db_pool {
        Some(pool) => {
            tracing::info!("using PostgresQuota");
            Arc::new(PostgresQuota::from_pool(pool))
        }
        None => Arc::new(InMemoryQuota::default()),
    }
}

async fn configure_credits(db_pool: Option<PgPool>) -> CreditsConfig {
    let ledger: Arc<dyn CreditLedger> = match db_pool {
        Some(pool) => {
            tracing::info!("using PostgresLedger");
            Arc::new(PostgresLedger::from_pool(pool))
        }
        None => Arc::new(InMemoryLedger::default()),
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

    let sandbox_budget_credits: u64 = env::var("SANDBOX_MONTHLY_CREDIT_BUDGET")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(25_000);
    let sandbox_window_days: u64 = env::var("SANDBOX_BUDGET_WINDOW_DAYS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(30);

    CreditsConfig {
        ledger,
        token_encryption_key,
        apple_verifier,
        grant_verifier,
        product_credits,
        sandbox_budget_credits,
        sandbox_budget_window: Duration::from_secs(sandbox_window_days * 24 * 60 * 60),
    }
}

fn configure_apple_verifier() -> Arc<dyn eigin_relay::credits::apple::AppleVerifier> {
    let apple_bundle_id = env::var("APPLE_BUNDLE_ID").unwrap_or_default();
    let apple_app_apple_id: Option<i64> = env::var("APPLE_APP_APPLE_ID")
        .ok()
        .and_then(|v| v.parse().ok());
    let root_certs = load_root_certs("config/apple");

    // A relay can accept more than one Apple environment. The production relay
    // accepts both `Production` (the live App Store) and `Sandbox` (TestFlight
    // and App Review, which always operate in sandbox); staging accepts only
    // `Sandbox`. Each environment gets its own pinned verifier; the bundle ID is
    // shared since it differs per relay, not per environment.
    let environments = env::var("APPLE_ENVIRONMENTS").unwrap_or_else(|_| "Sandbox".into());

    let (bundle_id, warn_missing) = if apple_bundle_id.is_empty() {
        tracing::warn!(
            "APPLE_BUNDLE_ID not set — Apple verification will fail for real transactions"
        );
        ("dev.placeholder".to_string(), true)
    } else {
        (apple_bundle_id, false)
    };
    let app_apple_id = if warn_missing {
        None
    } else {
        apple_app_apple_id
    };

    let verifiers: Vec<Box<dyn eigin_relay::credits::apple::AppleVerifier>> = environments
        .split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(|environment| {
            let verifier = AppStoreVerifier::new(
                root_certs.clone(),
                bundle_id.clone(),
                app_apple_id,
                environment,
            )
            .unwrap_or_else(|e| panic!("failed to create Apple verifier: {e}"));
            Box::new(verifier) as Box<dyn eigin_relay::credits::apple::AppleVerifier>
        })
        .collect();

    assert!(
        !verifiers.is_empty(),
        "APPLE_ENVIRONMENTS must list at least one environment"
    );

    Arc::new(MultiEnvironmentVerifier::new(verifiers))
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
