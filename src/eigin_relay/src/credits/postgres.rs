//! PostgreSQL-backed credit ledger using sqlx.
//!
//! Runs migrations from the `migrations/` directory on first use via
//! [`PostgresLedger::new`]. All mutations are designed to be atomic:
//! - `mint` uses INSERT with conflict detection on the (origin, fingerprint) unique index.
//! - `debit` is a single UPDATE that subtracts without a read-modify-write.
//! - `record_notification` uses INSERT ... ON CONFLICT DO NOTHING.

use async_trait::async_trait;
use sqlx::postgres::PgRow;
use sqlx::{PgPool, Row};
use uuid::Uuid;

use super::ledger::{CreditLedger, LedgerError, NewWallet, Wallet, WalletOrigin, WalletStatus};

pub struct PostgresLedger {
    pool: PgPool,
}

/// Connect to the database and run any pending migrations, returning the pool.
///
/// The pool is shared across components that talk to the same database (the
/// ledger and the quota), so it is built once here and handed to each.
pub async fn connect_and_migrate(database_url: &str) -> Result<PgPool, sqlx::Error> {
    let pool = PgPool::connect(database_url).await?;
    sqlx::migrate!("./migrations").run(&pool).await?;
    Ok(pool)
}

/// One-time, pre-rotation migration: stamp any wallet whose `key_fp` is still NULL with
/// the current key's fingerprint. This runs on startup right after migrations, before any
/// key rotation has happened, so every unstamped row is necessarily under the current key.
/// Idempotent — a no-op once every row is stamped.
pub async fn backfill_key_fp(pool: &PgPool, key_fp: &str) -> Result<u64, sqlx::Error> {
    let result = sqlx::query("UPDATE wallets SET key_fp = $1 WHERE key_fp IS NULL")
        .bind(key_fp)
        .execute(pool)
        .await?;
    Ok(result.rows_affected())
}

impl PostgresLedger {
    /// Connect to the database and run any pending migrations.
    pub async fn new(database_url: &str) -> Result<Self, sqlx::Error> {
        let pool = connect_and_migrate(database_url).await?;
        Ok(Self::from_pool(pool))
    }

    /// Build a ledger over an existing (already-migrated) pool.
    pub fn from_pool(pool: PgPool) -> Self {
        Self { pool }
    }
}

/// Postgres error code for unique constraint violations.
const PG_UNIQUE_VIOLATION: &str = "23505";

impl From<sqlx::Error> for LedgerError {
    fn from(e: sqlx::Error) -> Self {
        LedgerError::Internal(format!("database error: {e}"))
    }
}

impl TryFrom<&PgRow> for Wallet {
    type Error = LedgerError;

    fn try_from(row: &PgRow) -> Result<Self, Self::Error> {
        let origin = WalletOrigin::try_from(row.try_get::<&str, _>("origin")?)?;
        let status = WalletStatus::try_from(row.try_get::<&str, _>("status")?)?;
        Ok(Wallet {
            id: row.try_get("id")?,
            token_hash: row.try_get("token_hash")?,
            token_ciphertext: row.try_get("token_ciphertext")?,
            key_fp: row
                .try_get::<Option<String>, _>("key_fp")?
                .unwrap_or_default(),
            origin,
            fingerprint: row.try_get("fingerprint")?,
            product_id: row.try_get("product_id")?,
            initial_millicredits: row.try_get("initial_millicredits")?,
            balance_millicredits: row.try_get("balance_millicredits")?,
            status,
        })
    }
}

#[async_trait]
impl CreditLedger for PostgresLedger {
    async fn mint(&self, new: NewWallet<'_>) -> Result<Wallet, LedgerError> {
        let row = sqlx::query(
            r#"
            INSERT INTO wallets
                (token_hash, token_ciphertext, key_fp, origin, fingerprint, product_id,
                 initial_millicredits, balance_millicredits, status)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'active')
            RETURNING
                id, token_hash, token_ciphertext, key_fp, origin, fingerprint, product_id,
                initial_millicredits, balance_millicredits, status
            "#,
        )
        .bind(new.token_hash)
        .bind(new.token_ciphertext)
        .bind(new.key_fp)
        .bind(new.origin.as_str())
        .bind(new.fingerprint)
        .bind(new.product_id)
        .bind(new.millicredits) // initial_millicredits
        .bind(new.millicredits) // balance_millicredits — starts equal to initial
        .fetch_one(&self.pool)
        .await
        .map_err(|e| {
            // Postgres unique constraint violation code: 23505
            if let sqlx::Error::Database(ref db_err) = e {
                if db_err.code().as_deref() == Some(PG_UNIQUE_VIOLATION) {
                    return LedgerError::DuplicateFingerprint;
                }
            }
            LedgerError::from(e)
        })?;

        Wallet::try_from(&row)
    }

    async fn find_by_fingerprint(
        &self,
        origin: &WalletOrigin,
        fingerprint: &str,
    ) -> Result<Option<Wallet>, LedgerError> {
        let row = sqlx::query(
            r#"
            SELECT id, token_hash, token_ciphertext, key_fp, origin, fingerprint, product_id,
                   initial_millicredits, balance_millicredits, status
            FROM wallets
            WHERE origin = $1 AND fingerprint = $2
            "#,
        )
        .bind(origin.as_str())
        .bind(fingerprint)
        .fetch_optional(&self.pool)
        .await?;

        row.as_ref().map(Wallet::try_from).transpose()
    }

    async fn find_by_token_hash(&self, token_hash: &str) -> Result<Option<Wallet>, LedgerError> {
        let row = sqlx::query(
            r#"
            SELECT id, token_hash, token_ciphertext, key_fp, origin, fingerprint, product_id,
                   initial_millicredits, balance_millicredits, status
            FROM wallets
            WHERE token_hash = $1
            "#,
        )
        .bind(token_hash)
        .fetch_optional(&self.pool)
        .await?;

        row.as_ref().map(Wallet::try_from).transpose()
    }

    async fn debit(&self, wallet_id: Uuid, millicredits: i64) -> Result<(), LedgerError> {
        let result = sqlx::query(
            r#"
            UPDATE wallets
            SET balance_millicredits = balance_millicredits - $1,
                updated_at = now()
            WHERE id = $2
            "#,
        )
        .bind(millicredits)
        .bind(wallet_id)
        .execute(&self.pool)
        .await?;

        if result.rows_affected() == 0 {
            return Err(LedgerError::NotFound);
        }
        Ok(())
    }

    async fn close(&self, wallet_id: Uuid, status: WalletStatus) -> Result<(), LedgerError> {
        let result = sqlx::query(
            r#"
            UPDATE wallets
            SET balance_millicredits = 0,
                status = $1,
                updated_at = now()
            WHERE id = $2
            "#,
        )
        .bind(status.as_str())
        .bind(wallet_id)
        .execute(&self.pool)
        .await?;

        if result.rows_affected() == 0 {
            return Err(LedgerError::NotFound);
        }
        Ok(())
    }

    async fn record_notification(&self, notification_uuid: &str) -> Result<bool, LedgerError> {
        let result = sqlx::query(
            r#"
            INSERT INTO processed_notifications (notification_uuid)
            VALUES ($1)
            ON CONFLICT (notification_uuid) DO NOTHING
            "#,
        )
        .bind(notification_uuid)
        .execute(&self.pool)
        .await?;

        Ok(result.rows_affected() > 0)
    }
}

// Postgres integration tests: gated on DATABASE_URL being set. Run with:
//   DATABASE_URL=postgres://... cargo test -- --ignored
#[cfg(test)]
mod tests {
    use super::*;

    async fn test_ledger() -> Option<PostgresLedger> {
        let url = std::env::var("DATABASE_URL").ok()?;
        Some(PostgresLedger::new(&url).await.expect("failed to connect"))
    }

    fn origin() -> WalletOrigin {
        WalletOrigin::AppleAppStore
    }

    #[tokio::test]
    #[ignore = "requires DATABASE_URL"]
    async fn postgres_mint_and_find() {
        let Some(ledger) = test_ledger().await else {
            return;
        };
        let fp = Uuid::new_v4().to_string();
        let wallet = ledger
            .mint(NewWallet {
                origin: &origin(),
                fingerprint: &fp,
                product_id: "prod.500",
                millicredits: 500_000,
                token_hash: &format!("hash_{fp}"),
                token_ciphertext: "cipher",
                key_fp: "fp0",
            })
            .await
            .unwrap();
        assert_eq!(wallet.balance_millicredits, 500_000);

        let found = ledger.find_by_fingerprint(&origin(), &fp).await.unwrap();
        assert!(found.is_some());
    }

    #[tokio::test]
    #[ignore = "requires DATABASE_URL"]
    async fn postgres_debit_is_atomic() {
        let Some(ledger) = test_ledger().await else {
            return;
        };
        let fp = Uuid::new_v4().to_string();
        let wallet = ledger
            .mint(NewWallet {
                origin: &origin(),
                fingerprint: &fp,
                product_id: "prod.500",
                millicredits: 500_000,
                token_hash: &format!("hash_{fp}"),
                token_ciphertext: "cipher",
                key_fp: "fp0",
            })
            .await
            .unwrap();
        ledger.debit(wallet.id, 1000).await.unwrap();
        let updated = ledger
            .find_by_token_hash(&wallet.token_hash)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(updated.balance_millicredits, 499_000);
    }

    #[tokio::test]
    #[ignore = "requires DATABASE_URL"]
    async fn postgres_notification_idempotency() {
        let Some(ledger) = test_ledger().await else {
            return;
        };
        let uuid = Uuid::new_v4().to_string();
        assert!(ledger.record_notification(&uuid).await.unwrap());
        assert!(!ledger.record_notification(&uuid).await.unwrap());
    }
}
