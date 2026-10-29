//! Opt-in fault injection against a disposable PostgreSQL database.
//! Run with POOL_TEST_DATABASE_URL set; this test never runs migrations.

use std::{str::FromStr, time::Duration};

use sqlx::{
    Connection, PgConnection,
    postgres::{PgConnectOptions, PgPoolOptions},
};
use tokio::{
    net::{TcpListener, TcpStream},
    sync::oneshot,
    task::JoinSet,
    time::{sleep, timeout},
};

/// A silent established socket must not permanently consume the only pool slot.
#[tokio::test]
#[ignore = "requires disposable PostgreSQL via POOL_TEST_DATABASE_URL"]
async fn pool_recovers_after_silent_connection_return() {
    timeout(Duration::from_secs(25), check_recovery())
        .await
        .expect("fault-injection check exceeded its deadline");
}

async fn check_recovery() {
    let url = std::env::var("POOL_TEST_DATABASE_URL")
        .expect("set POOL_TEST_DATABASE_URL to a disposable local PostgreSQL database");
    let endpoint = url::Url::parse(&url).expect("valid database URL");
    let host = endpoint.host_str().expect("database host").to_owned();
    let port = endpoint.port().unwrap_or(5432);
    assert!(
        matches!(host.as_str(), "localhost" | "127.0.0.1" | "::1"),
        "use a local disposable database"
    );
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let proxy_port = listener.local_addr().unwrap().port();
    let (interrupt, interrupted) = oneshot::channel();
    let (acknowledge, acknowledged) = oneshot::channel();

    let proxy = tokio::spawn(async move {
        let mut tasks = JoinSet::new();
        let mut fault = Some((interrupted, acknowledge));
        loop {
            let (mut client, _) = listener.accept().await.unwrap();
            let mut server = TcpStream::connect((host.as_str(), port)).await.unwrap();
            let fault = fault.take();
            tasks.spawn(async move {
                if let Some((interrupted, acknowledge)) = fault {
                    tokio::select! {
                        _ = tokio::io::copy_bidirectional(&mut client, &mut server) => return,
                        _ = interrupted => {}
                    }
                    let _ = acknowledge.send(());
                    // Stall this socket while subsequent connections remain healthy.
                    std::future::pending::<()>().await;
                    drop((client, server));
                } else {
                    let _ = tokio::io::copy_bidirectional(&mut client, &mut server).await;
                }
            });
        }
    });
    // Aborting the accept task drops its JoinSet and closes all proxy sockets.
    struct AbortProxy(tokio::task::JoinHandle<()>);
    impl Drop for AbortProxy {
        fn drop(&mut self) {
            self.0.abort();
        }
    }
    let _proxy = AbortProxy(proxy);

    let options = PgConnectOptions::from_str(&url)
        .unwrap()
        .host("127.0.0.1")
        .port(proxy_port);
    let pool = PgPoolOptions::new()
        .max_connections(1)
        .acquire_timeout(Duration::from_millis(500))
        .connect_with(options.clone())
        .await
        .unwrap();
    let mut connection = pool.acquire().await.unwrap();
    sqlx::query("SELECT 1")
        .execute(&mut *connection)
        .await
        .unwrap();
    interrupt.send(()).unwrap();
    acknowledged.await.unwrap();
    drop(connection);

    let mut fresh = PgConnection::connect_with(&options).await.unwrap();
    sqlx::query("SELECT 1").execute(&mut fresh).await.unwrap();
    drop(fresh);

    let recovered = timeout(Duration::from_secs(12), async {
        loop {
            if sqlx::query("SELECT 1").execute(&pool).await.is_ok() {
                break;
            }
            eprintln!(
                "pool unavailable: size={} idle={}",
                pool.size(),
                pool.num_idle()
            );
            sleep(Duration::from_millis(100)).await;
        }
    })
    .await;
    assert!(
        recovered.is_ok(),
        "fresh connection succeeds, but original pool did not recover: size={} idle={}",
        pool.size(),
        pool.num_idle()
    );
    timeout(Duration::from_secs(2), pool.close())
        .await
        .expect("pool shutdown stalled");
}

fn local_options() -> PgConnectOptions {
    let url = std::env::var("POOL_TEST_DATABASE_URL")
        .expect("set POOL_TEST_DATABASE_URL to a disposable local PostgreSQL database");
    let endpoint = url::Url::parse(&url).unwrap();
    assert!(
        matches!(endpoint.host_str(), Some("localhost" | "127.0.0.1" | "::1")),
        "use a local disposable database"
    );
    PgConnectOptions::from_str(&url).unwrap()
}

/// Healthy returns reuse the connection and flush dropped transaction rollbacks.
#[tokio::test]
#[ignore = "requires disposable PostgreSQL via POOL_TEST_DATABASE_URL"]
async fn healthy_return_reuses_connection_and_rolls_back() {
    timeout(Duration::from_secs(15), async {
        let pool = PgPoolOptions::new()
            .max_connections(1)
            .acquire_timeout(Duration::from_secs(2))
            .connect_with(local_options())
            .await
            .unwrap();
        let pid: i32 = sqlx::query_scalar("SELECT pg_backend_pid()")
            .fetch_one(&pool)
            .await
            .unwrap();
        sqlx::query("CREATE TEMP TABLE pool_return_check (value integer)")
            .execute(&pool)
            .await
            .unwrap();
        let mut tx = pool.begin().await.unwrap();
        sqlx::query("INSERT INTO pool_return_check VALUES (1)")
            .execute(&mut *tx)
            .await
            .unwrap();
        drop(tx);
        let count: i64 = sqlx::query_scalar("SELECT count(*) FROM pool_return_check")
            .fetch_one(&pool)
            .await
            .unwrap();
        assert_eq!(count, 0, "dropped transaction must roll back");
        for _ in 0..20 {
            let reused_pid: i32 = sqlx::query_scalar("SELECT pg_backend_pid()")
                .fetch_one(&pool)
                .await
                .unwrap();
            assert_eq!(pid, reused_pid, "healthy connections should be reused");
        }
        pool.close().await;
    })
    .await
    .expect("healthy return check stalled");
}

/// The deadline covers callbacks as well as ping; minimum-size maintenance survives.
#[tokio::test]
#[ignore = "requires disposable PostgreSQL via POOL_TEST_DATABASE_URL"]
async fn stalled_release_callback_releases_permit_and_replenishes_minimum() {
    use std::sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    };
    timeout(Duration::from_secs(15), async {
        let stall = Arc::new(AtomicBool::new(true));
        let callback_stall = stall.clone();
        let pool = PgPoolOptions::new()
            .max_connections(1)
            .min_connections(1)
            .acquire_timeout(Duration::from_secs(2))
            .after_release(move |_, _| {
                let should_stall = callback_stall.swap(false, Ordering::SeqCst);
                Box::pin(async move {
                    if should_stall {
                        std::future::pending::<()>().await;
                    }
                    Ok(true)
                })
            })
            .connect_with(local_options())
            .await
            .unwrap();
        let mut connection = pool.acquire().await.unwrap();
        let original_pid: i32 = sqlx::query_scalar("SELECT pg_backend_pid()")
            .fetch_one(&mut *connection)
            .await
            .unwrap();
        drop(connection);
        timeout(Duration::from_secs(10), async {
            while stall.load(Ordering::SeqCst) || pool.num_idle() != 1 {
                sleep(Duration::from_millis(20)).await;
            }
        })
        .await
        .expect("minimum connection count was not replenished");
        let new_pid: i32 = sqlx::query_scalar("SELECT pg_backend_pid()")
            .fetch_one(&pool)
            .await
            .unwrap();
        assert_ne!(
            original_pid, new_pid,
            "timed-out connection must be discarded"
        );
        pool.close().await;
    })
    .await
    .expect("callback recovery check stalled");
}

/// A cancelled long-running query cannot hold the pool slot past cleanup's deadline.
#[tokio::test]
#[ignore = "requires disposable PostgreSQL via POOL_TEST_DATABASE_URL"]
async fn cancelled_query_allows_replacement() {
    timeout(Duration::from_secs(15), async {
        let pool = PgPoolOptions::new()
            .max_connections(1)
            .acquire_timeout(Duration::from_secs(10))
            .connect_with(local_options())
            .await
            .unwrap();
        let mut connection = pool.acquire().await.unwrap();
        let original_pid: i32 = sqlx::query_scalar("SELECT pg_backend_pid()")
            .fetch_one(&mut *connection)
            .await
            .unwrap();
        let mut observer = PgConnection::connect_with(&local_options()).await.unwrap();
        {
            let query = sqlx::query("SELECT pg_sleep(30)").execute(&mut *connection);
            tokio::pin!(query);
            tokio::select! {
                result = &mut query => panic!("query ended before cancellation: {result:?}"),
                _ = async {
                    loop {
                        let sleeping: bool = sqlx::query_scalar(
                            "SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE pid = $1 AND wait_event = 'PgSleep')"
                        ).bind(original_pid).fetch_one(&mut observer).await.unwrap();
                        if sleeping { break; }
                        sleep(Duration::from_millis(20)).await;
                    }
                } => {}
            }
            // Drop the query only after the observer confirms server-side execution.
        }
        drop(connection);
        drop(observer);
        let new_pid: i32 = sqlx::query_scalar("SELECT pg_backend_pid()")
            .fetch_one(&pool)
            .await
            .unwrap();
        assert_ne!(
            original_pid, new_pid,
            "connection still executing must be discarded"
        );
        pool.close().await;
    })
    .await
    .expect("cancelled query prevented recovery");
}
