use std::env;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use axum::Router;
use axum::middleware;
use axum::routing::get;
use tower_http::trace::TraceLayer;
use tracing_subscriber::EnvFilter;

use eigin_relay::{AppState, Pool, RateLimiter, create_client, health, require_eigin_key, search};

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::from_default_env().add_directive("eigin_relay=info".parse().unwrap()),
        )
        .init();

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
    let pool_path = env::var("POOL_FILE_PATH").unwrap_or_else(|_| "/data/pool.json".into());
    let port: u16 = env::var("PORT")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(8080);

    let search_client = create_client(reqwest::Client::new(), &search_api_url);

    let state = Arc::new(AppState {
        search_client,
        mojeek_api_key,
        eigin_relay_key,
        pool: Pool::load(PathBuf::from(pool_path), pool_size),
        rate_limiter: RateLimiter::new(
            rate_limit_requests,
            Duration::from_secs(rate_limit_window_secs),
        ),
    });

    let routes_with_auth =
        Router::new()
            .route("/search", get(search::handle))
            .layer(middleware::from_fn_with_state(
                state.clone(),
                require_eigin_key,
            ));

    let app = Router::new()
        .route("/health", get(health))
        .merge(routes_with_auth)
        .layer(TraceLayer::new_for_http())
        .with_state(state);

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
