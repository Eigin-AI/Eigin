//! PostgreSQL-backed rolling-window quota, stored as daily counters.
//!
//! Each `(key, UTC day)` is one row holding that day's total. A consume reads
//! `SUM(used)` over the buckets within the trailing window — at most ~window-in-days
//! rows — then increments today's bucket via upsert. The check-and-increment is
//! serialized per key with a transaction advisory lock; because the sum touches
//! only a handful of bucket rows, the lock is held only briefly even under load.

use std::time::Duration;

use async_trait::async_trait;
use sqlx::PgPool;
use time::{Date, OffsetDateTime};

use super::bucket::window_bounds;
use super::{Quota, QuotaError};

pub struct PostgresQuota {
    pool: PgPool,
}

impl PostgresQuota {
    /// Build a quota over an existing pool. The pool is shared with the ledger;
    /// migrations are run once by whoever owns pool construction.
    pub fn from_pool(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Consume against the window ending at `now`. The trait method calls this
    /// with the real clock; tests pass a fixed `now` to exercise day rollover.
    async fn try_consume_at(
        &self,
        key: &str,
        amount: u64,
        max: u64,
        window: Duration,
        now: OffsetDateTime,
    ) -> Result<(), QuotaError> {
        let (today, cutoff) = window_bounds(window, now);
        let mut tx = self.pool.begin().await?;

        // Serialize concurrent consumers of the same key so the SUM check and the
        // upsert are atomic. Only same-key callers contend, and the critical section
        // is a sum over a handful of bucket rows. Releases at transaction end.
        sqlx::query("SELECT pg_advisory_xact_lock(hashtext($1))")
            .bind(key)
            .execute(&mut *tx)
            .await?;

        let used = sum_window(&mut *tx, key, cutoff).await?;
        if used + amount > max {
            // Rollback releases the advisory lock; nothing is recorded.
            tx.rollback().await?;
            return Err(QuotaError::Exhausted);
        }

        // Drop buckets that have aged out of every key's window to keep the table small.
        sqlx::query("DELETE FROM quota_buckets WHERE key = $1 AND bucket < $2")
            .bind(key)
            .bind(cutoff)
            .execute(&mut *tx)
            .await?;

        sqlx::query(
            r#"
            INSERT INTO quota_buckets (key, bucket, used)
            VALUES ($1, $2, $3)
            ON CONFLICT (key, bucket) DO UPDATE SET used = quota_buckets.used + EXCLUDED.used
            "#,
        )
        .bind(key)
        .bind(today)
        .bind(amount as i64)
        .execute(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok(())
    }

    async fn remaining_at(
        &self,
        key: &str,
        max: u64,
        window: Duration,
        now: OffsetDateTime,
    ) -> Result<u64, QuotaError> {
        let (_, cutoff) = window_bounds(window, now);
        let used = sum_window(&self.pool, key, cutoff).await?;
        Ok(max.saturating_sub(used))
    }
}

impl From<sqlx::Error> for QuotaError {
    fn from(e: sqlx::Error) -> Self {
        QuotaError::Internal(format!("database error: {e}"))
    }
}

/// Sum the buckets for `key` at or after `cutoff`.
async fn sum_window<'e, E>(executor: E, key: &str, cutoff: Date) -> Result<u64, QuotaError>
where
    E: sqlx::PgExecutor<'e>,
{
    let used: i64 = sqlx::query_scalar(
        r#"
        SELECT COALESCE(SUM(used), 0)::bigint
        FROM quota_buckets
        WHERE key = $1 AND bucket >= $2
        "#,
    )
    .bind(key)
    .bind(cutoff)
    .fetch_one(executor)
    .await?;
    Ok(used.max(0) as u64)
}

#[async_trait]
impl Quota for PostgresQuota {
    async fn try_consume(
        &self,
        key: &str,
        amount: u64,
        max: u64,
        window: Duration,
    ) -> Result<(), QuotaError> {
        self.try_consume_at(key, amount, max, window, OffsetDateTime::now_utc())
            .await
    }

    async fn remaining(&self, key: &str, max: u64, window: Duration) -> Result<u64, QuotaError> {
        self.remaining_at(key, max, window, OffsetDateTime::now_utc())
            .await
    }
}

// Postgres integration tests: gated on DATABASE_URL being set. Run with:
//   DATABASE_URL=postgres://... cargo test -- --ignored
#[cfg(test)]
mod tests {
    use super::*;

    async fn test_quota() -> Option<PostgresQuota> {
        let url = std::env::var("DATABASE_URL").ok()?;
        let pool = crate::credits::postgres::connect_and_migrate(&url)
            .await
            .expect("failed to connect");
        Some(PostgresQuota::from_pool(pool))
    }

    fn unique_key() -> String {
        format!("test_{}", uuid::Uuid::new_v4())
    }

    const WINDOW: Duration = Duration::from_secs(30 * 24 * 60 * 60);

    fn day(n: i64) -> OffsetDateTime {
        OffsetDateTime::UNIX_EPOCH + time::Duration::days(20_000 + n)
    }

    #[tokio::test]
    #[ignore = "requires DATABASE_URL"]
    async fn consumes_up_to_max_then_rejects() {
        let Some(quota) = test_quota().await else {
            return;
        };
        let key = unique_key();
        let now = day(0);
        quota
            .try_consume_at(&key, 400, 1000, WINDOW, now)
            .await
            .unwrap();
        quota
            .try_consume_at(&key, 500, 1000, WINDOW, now)
            .await
            .unwrap();
        assert!(matches!(
            quota.try_consume_at(&key, 200, 1000, WINDOW, now).await,
            Err(QuotaError::Exhausted)
        ));
        assert_eq!(
            quota.remaining_at(&key, 1000, WINDOW, now).await.unwrap(),
            100
        );
    }

    #[tokio::test]
    #[ignore = "requires DATABASE_URL"]
    async fn keys_are_independent() {
        let Some(quota) = test_quota().await else {
            return;
        };
        let a = unique_key();
        let b = unique_key();
        let now = day(0);
        quota.try_consume_at(&a, 10, 10, WINDOW, now).await.unwrap();
        quota.try_consume_at(&b, 10, 10, WINDOW, now).await.unwrap();
        assert_eq!(quota.remaining_at(&a, 10, WINDOW, now).await.unwrap(), 0);
        assert_eq!(quota.remaining_at(&b, 10, WINDOW, now).await.unwrap(), 0);
    }

    #[tokio::test]
    #[ignore = "requires DATABASE_URL"]
    async fn buckets_age_out_of_window() {
        let Some(quota) = test_quota().await else {
            return;
        };
        let key = unique_key();
        // A 2-day window: today and yesterday count; older days do not.
        let window = Duration::from_secs(2 * 24 * 60 * 60);
        quota
            .try_consume_at(&key, 10, 10, window, day(0))
            .await
            .unwrap();
        assert!(matches!(
            quota.try_consume_at(&key, 1, 10, window, day(1)).await,
            Err(QuotaError::Exhausted)
        ));
        // Two days later the original bucket has aged out — headroom is restored.
        quota
            .try_consume_at(&key, 10, 10, window, day(2))
            .await
            .unwrap();
    }
}
