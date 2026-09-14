use std::collections::HashMap;
use std::env;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use tracing_subscriber::EnvFilter;

use eigin_relay::assets::store::{AssetStore, InertAssetStore};
use eigin_relay::assets::{AssetsConfig, ScalewayAssetStore};
use eigin_relay::credits::apple::{AppStoreVerifier, MultiEnvironmentVerifier, load_root_certs};
use eigin_relay::credits::grant::{Ed25519GrantVerifier, GrantVerifier, RejectingGrantVerifier};
use eigin_relay::credits::postgres::{backfill_key_fp, connect_and_migrate};
use eigin_relay::credits::token::{fingerprint, parse_encryption_key};
use eigin_relay::credits::{CreditLedger, InMemoryLedger, PostgresLedger};
use eigin_relay::inference::catalog::{
    ModelsConfig, ProductsConfig, ProvidersConfig, ResolvedCatalog,
};
use eigin_relay::inference::upstream::{ReqwestUpstreamClient, UpstreamClient};
use eigin_relay::quota::{InMemoryQuota, PostgresQuota, Quota};
use eigin_relay::{AppState, RateLimiter, build_router, create_client};
use sqlx::PgPool;

// ── Config structs ────────────────────────────────────────────────────────────

struct SearchConfig {
    client: Arc<dyn eigin_relay::search::SearchClient>,
    staan_api_key: String,
    pool_max: u64,
    window: Duration,
    rate_limiter: RateLimiter,
}

struct CreditsConfig {
    ledger: Arc<dyn CreditLedger>,
    token_encryption_key: [u8; 32],
    token_encryption_key_secondary: Option<[u8; 32]>,
    apple_verifier: Arc<dyn eigin_relay::credits::apple::AppleVerifier>,
    grant_verifier: Arc<dyn eigin_relay::credits::grant::GrantVerifier>,
    product_credits: HashMap<String, i64>,
    sandbox_budget_credits: u64,
    sandbox_budget_window: Duration,
}

struct InferenceConfig {
    provider_clients: HashMap<String, Arc<dyn UpstreamClient>>,
    provider_keys: HashMap<String, String>,
    resolved_catalog: ResolvedCatalog,
    token_rate_limiter: RateLimiter<uuid::Uuid>,
}

struct AssetsModuleConfig {
    assets_config: HashMap<String, eigin_relay::assets::catalog::AssetConfig>,
    asset_store: Arc<dyn AssetStore>,
    presign_expiry: Duration,
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
    let assets = configure_assets();
    let webhook_rate_limiter = configure_webhook_rate_limiter();

    // Trusted proxy hops in front of the app, for reading the client IP from
    // `X-Forwarded-For`. Defaults to 1 (Scaleway's ingress); verify empirically.
    let trusted_proxy_hops: usize = env::var("TRUSTED_PROXY_HOPS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(1);

    let state = Arc::new(AppState {
        search_client: search.client,
        staan_api_key: search.staan_api_key,
        eigin_relay_keys,
        ip_rate_limiter: search.rate_limiter,
        trusted_proxy_hops,
        webhook_rate_limiter,
        search_pool_max: search.pool_max,
        search_window: search.window,
        quota,
        ledger: credits.ledger,
        apple_verifier: credits.apple_verifier,
        grant_verifier: credits.grant_verifier,
        product_credits: credits.product_credits,
        token_encryption_key: credits.token_encryption_key,
        token_encryption_key_secondary: credits.token_encryption_key_secondary,
        sandbox_budget_credits: credits.sandbox_budget_credits,
        sandbox_budget_window: credits.sandbox_budget_window,
        provider_clients: inference.provider_clients,
        provider_keys: inference.provider_keys,
        canonical_models: inference.resolved_catalog.canonical_models,
        alias_map: inference.resolved_catalog.alias_map,
        token_rate_limiter: inference.token_rate_limiter,
        assets_config: assets.assets_config,
        assets_cache: Default::default(),
        asset_store: assets.asset_store,
        presign_expiry: assets.presign_expiry,
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
    let staan_api_key = env::var("STAAN_API_KEY").expect("STAAN_API_KEY must be set");
    let search_api_url =
        env::var("SEARCH_API_URL").unwrap_or_else(|_| "https://api.staan.ai/v2".to_string());
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

    let client = create_client(eigin_relay::search::http_client(), &search_api_url);
    let rate_limiter = RateLimiter::new(
        rate_limit_requests,
        Duration::from_secs(rate_limit_window_secs),
    );

    SearchConfig {
        client,
        staan_api_key,
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

/// Per-IP limiter for the unauthenticated Apple webhook. Apple's V2 retry
/// schedule spaces attempts 1, 12, 24, 48, and 72 hours apart, so real
/// traffic sits far below the default — generous enough to never block Apple,
/// low enough to bound the cost of a flood.
fn configure_webhook_rate_limiter() -> RateLimiter {
    let requests: u32 = env::var("WEBHOOK_RATE_LIMIT_REQUESTS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(20);
    let window_secs: u64 = env::var("WEBHOOK_RATE_LIMIT_WINDOW_SECONDS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(60);
    RateLimiter::new(requests, Duration::from_secs(window_secs))
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
    // Treat an empty value as unset: `just run relay` exports the var unconditionally, so
    // a missing .env entry arrives as "" rather than absent. A non-empty but malformed key
    // is still a hard error.
    //
    // With a database configured (i.e. a real deployment) a missing key is fatal: booting on
    // the insecure dev key would make existing ciphertext undecryptable and persist tokens
    // encrypted under all-zeros — damage that survives fixing the config. The dev-key
    // fallback is kept only for the in-memory ledger path (`just run relay`).
    let token_encryption_key = env::var("TOKEN_ENCRYPTION_KEY_PRIMARY")
        .ok()
        .filter(|v| !v.trim().is_empty())
        .map(|v| parse_encryption_key(&v).expect("invalid TOKEN_ENCRYPTION_KEY_PRIMARY"))
        .unwrap_or_else(|| {
            assert!(
                db_pool.is_none(),
                "TOKEN_ENCRYPTION_KEY_PRIMARY must be set when DATABASE_URL is configured"
            );
            tracing::warn!(
                "TOKEN_ENCRYPTION_KEY_PRIMARY not set — using insecure dev key (in-memory ledger only)"
            );
            [0u8; 32]
        });

    // The secondary key is present only during a rotation window; it lets restore decrypt
    // tokens still encrypted under the previous key until a sweep re-encrypts them.
    let token_encryption_key_secondary = env::var("TOKEN_ENCRYPTION_KEY_SECONDARY")
        .ok()
        .filter(|v| !v.trim().is_empty())
        .map(|v| parse_encryption_key(&v).expect("invalid TOKEN_ENCRYPTION_KEY_SECONDARY"));
    if token_encryption_key_secondary.is_some() {
        tracing::info!("TOKEN_ENCRYPTION_KEY_SECONDARY set — key rotation in progress");
    }

    let ledger: Arc<dyn CreditLedger> = match db_pool {
        Some(pool) => {
            tracing::info!("using PostgresLedger");
            // One-time, pre-rotation backfill: stamp existing rows with the current key's
            // fingerprint. Safe because no rotation has happened yet, so every unstamped
            // row is under this key. Idempotent on subsequent boots.
            match backfill_key_fp(&pool, &fingerprint(&token_encryption_key)).await {
                Ok(n) if n > 0 => tracing::info!("backfilled key_fp on {n} wallet(s)"),
                Ok(_) => {}
                Err(e) => tracing::error!("key_fp backfill failed: {e}"),
            }
            Arc::new(PostgresLedger::from_pool(pool))
        }
        None => Arc::new(InMemoryLedger::default()),
    };

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
        token_encryption_key_secondary,
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

    // A relay can accept more than one Apple environment and more than one
    // bundle ID. The production relay accepts both `Production` (the live App
    // Store) and `Sandbox` (TestFlight and App Review, which always operate in
    // sandbox); staging accepts only `Sandbox`. Multiple bundle IDs let a single
    // relay serve several apps at once — e.g. the legacy alpha alongside a new
    // App Store release during a bundle-ID migration, or per-customer builds.
    // Each (bundle ID × environment) pair gets its own pinned verifier.
    let environments = env::var("APPLE_ENVIRONMENTS").unwrap_or_else(|_| "Sandbox".into());

    let (bundle_ids, warn_missing) = if apple_bundle_id.trim().is_empty() {
        tracing::warn!(
            "APPLE_BUNDLE_ID not set — Apple verification will fail for real transactions"
        );
        (vec!["dev.placeholder".to_string()], true)
    } else {
        let ids: Vec<String> = apple_bundle_id
            .split(',')
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(str::to_string)
            .collect();
        (ids, false)
    };
    let app_apple_id = if warn_missing {
        None
    } else {
        apple_app_apple_id
    };

    let environments: Vec<String> = environments
        .split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
        .collect();

    let verifiers: Vec<Box<dyn eigin_relay::credits::apple::AppleVerifier>> = bundle_ids
        .iter()
        .flat_map(|bundle_id| {
            environments.iter().map(|environment| {
                let verifier = AppStoreVerifier::new(
                    root_certs.clone(),
                    bundle_id.clone(),
                    app_apple_id,
                    environment,
                )
                .unwrap_or_else(|e| panic!("failed to create Apple verifier: {e}"));
                Box::new(verifier) as Box<dyn eigin_relay::credits::apple::AppleVerifier>
            })
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
    let resolved_catalog = ModelsConfig::load(&models_config_path)
        .and_then(|c| c.into_resolved())
        .unwrap_or_else(|e| {
            tracing::warn!("{e} — no models available");
            ResolvedCatalog {
                canonical_models: HashMap::new(),
                alias_map: HashMap::new(),
            }
        });

    let mut provider_clients: HashMap<String, Arc<dyn UpstreamClient>> = HashMap::new();
    let mut provider_keys: HashMap<String, String> = HashMap::new();

    let providers_config_path =
        env::var("PROVIDERS_CONFIG_PATH").unwrap_or_else(|_| "config/providers.toml".into());

    match ProvidersConfig::load(&providers_config_path) {
        Ok(providers_config) => {
            for provider in providers_config.providers {
                let env_key = format!("PROVIDER_{}_API_KEY", provider.id.to_uppercase());
                match env::var(&env_key) {
                    Ok(key) if !key.trim().is_empty() => {
                        let id = provider.id;
                        tracing::info!(
                            provider_id = %id,
                            base_url = %provider.base_url,
                            "configured upstream provider"
                        );
                        let client = Arc::new(ReqwestUpstreamClient::new(
                            eigin_relay::inference::upstream::http_client(),
                            provider.base_url,
                            id.clone(),
                        )) as Arc<dyn UpstreamClient>;
                        provider_clients.insert(id.clone(), client);
                        provider_keys.insert(id, key);
                    }
                    _ => {
                        tracing::error!(
                            provider_id = %provider.id,
                            env_key = %env_key,
                            "provider configured but no API key found — inference for this provider will fail"
                        );
                    }
                }
            }
        }
        Err(e) => {
            tracing::warn!("{e} — no providers configured");
        }
    }

    if provider_clients.is_empty() {
        tracing::warn!("no upstream providers configured — inference routes will return 503");
    }

    let token_rate_limiter = RateLimiter::new(
        token_rate_limit_requests,
        Duration::from_secs(token_rate_limit_window_secs),
    );

    InferenceConfig {
        provider_clients,
        provider_keys,
        resolved_catalog,
        token_rate_limiter,
    }
}

/// Load assets.toml + the object store. With no env config the module is inert:
/// an empty catalog lists nothing and unknown ids 404. Entries present but no
/// store configured 503 at serve time (dev can point assets.toml at a local
/// fake or leave it empty).
fn configure_assets() -> AssetsModuleConfig {
    let assets_config_path =
        env::var("ASSETS_CONFIG_PATH").unwrap_or_else(|_| "config/assets.toml".into());
    let assets_config = AssetsConfig::load(&assets_config_path)
        .and_then(|c| c.into_map())
        .unwrap_or_else(|e| {
            tracing::warn!("{e} — asset module disabled");
            HashMap::new()
        });

    let asset_store: Arc<dyn AssetStore> = match ScalewayAssetStore::from_env() {
        Some(store) => {
            tracing::info!("asset mirror store configured");
            Arc::new(store)
        }
        None => {
            tracing::info!("no asset store configured — /v1/assets entries will 503");
            Arc::new(InertAssetStore)
        }
    };

    let presign_expiry = Duration::from_secs(
        env::var("PRESIGN_EXPIRY_SECONDS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(86_400),
    );

    AssetsModuleConfig {
        assets_config,
        asset_store,
        presign_expiry,
    }
}
