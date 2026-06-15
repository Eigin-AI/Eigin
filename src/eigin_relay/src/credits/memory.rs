//! In-memory credit ledger for tests and dev.
//!
//! Not safe for production use — all state is lost on restart and there is
//! no persistence. Used in tests via `InMemoryLedger::default()`.

use std::collections::HashMap;
use std::sync::Mutex;

use async_trait::async_trait;
use uuid::Uuid;

use super::ledger::{CreditLedger, LedgerError, Wallet, WalletOrigin, WalletStatus};

#[derive(Default)]
pub struct InMemoryLedger {
    inner: Mutex<Inner>,
}

#[derive(Default)]
struct Inner {
    wallets: Vec<Wallet>,
    notifications: HashMap<String, ()>,
}

#[async_trait]
impl CreditLedger for InMemoryLedger {
    async fn mint(
        &self,
        origin: &WalletOrigin,
        fingerprint: &str,
        product_id: &str,
        millicredits: i64,
        token_hash: &str,
        token_ciphertext: &str,
    ) -> Result<Wallet, LedgerError> {
        let mut inner = self.inner.lock().unwrap();

        // Enforce the (origin, fingerprint) uniqueness constraint.
        if inner
            .wallets
            .iter()
            .any(|w| w.origin == *origin && w.fingerprint == fingerprint)
        {
            return Err(LedgerError::DuplicateFingerprint);
        }

        let wallet = Wallet {
            id: Uuid::new_v4(),
            token_hash: token_hash.to_owned(),
            token_ciphertext: token_ciphertext.to_owned(),
            origin: origin.clone(),
            fingerprint: fingerprint.to_owned(),
            product_id: product_id.to_owned(),
            initial_millicredits: millicredits,
            balance_millicredits: millicredits,
            status: WalletStatus::Active,
        };
        inner.wallets.push(wallet.clone());
        Ok(wallet)
    }

    async fn find_by_fingerprint(
        &self,
        origin: &WalletOrigin,
        fingerprint: &str,
    ) -> Result<Option<Wallet>, LedgerError> {
        let inner = self.inner.lock().unwrap();
        Ok(inner
            .wallets
            .iter()
            .find(|w| w.origin == *origin && w.fingerprint == fingerprint)
            .cloned())
    }

    async fn find_by_token_hash(&self, token_hash: &str) -> Result<Option<Wallet>, LedgerError> {
        let inner = self.inner.lock().unwrap();
        Ok(inner
            .wallets
            .iter()
            .find(|w| w.token_hash == token_hash)
            .cloned())
    }

    async fn debit(&self, wallet_id: Uuid, millicredits: i64) -> Result<(), LedgerError> {
        let mut inner = self.inner.lock().unwrap();
        let wallet = inner
            .wallets
            .iter_mut()
            .find(|w| w.id == wallet_id)
            .ok_or(LedgerError::NotFound)?;
        // Atomic in memory: the Mutex guarantees no concurrent modification.
        wallet.balance_millicredits -= millicredits;
        Ok(())
    }

    async fn close(&self, wallet_id: Uuid, status: WalletStatus) -> Result<(), LedgerError> {
        let mut inner = self.inner.lock().unwrap();
        let wallet = inner
            .wallets
            .iter_mut()
            .find(|w| w.id == wallet_id)
            .ok_or(LedgerError::NotFound)?;
        wallet.balance_millicredits = 0;
        wallet.status = status;
        Ok(())
    }

    async fn record_notification(&self, notification_uuid: &str) -> Result<bool, LedgerError> {
        let mut inner = self.inner.lock().unwrap();
        let is_new = inner
            .notifications
            .insert(notification_uuid.to_owned(), ())
            .is_none();
        Ok(is_new)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn origin() -> WalletOrigin {
        WalletOrigin::AppleAppStore
    }

    async fn mint_test_wallet(ledger: &InMemoryLedger, fingerprint: &str) -> Wallet {
        ledger
            .mint(
                &origin(),
                fingerprint,
                "prod.500",
                500_000,
                "hash1",
                "cipher1",
            )
            .await
            .unwrap()
    }

    #[tokio::test]
    async fn mint_creates_wallet_with_full_balance() {
        let ledger = InMemoryLedger::default();
        let wallet = mint_test_wallet(&ledger, "fp1").await;
        assert_eq!(wallet.balance_millicredits, 500_000);
        assert_eq!(wallet.status, WalletStatus::Active);
    }

    #[tokio::test]
    async fn mint_duplicate_fingerprint_returns_error() {
        let ledger = InMemoryLedger::default();
        mint_test_wallet(&ledger, "fp1").await;
        let err = ledger
            .mint(&origin(), "fp1", "prod.500", 500_000, "hash2", "cipher2")
            .await
            .unwrap_err();
        assert!(matches!(err, LedgerError::DuplicateFingerprint));
    }

    #[tokio::test]
    async fn find_by_fingerprint_returns_wallet() {
        let ledger = InMemoryLedger::default();
        mint_test_wallet(&ledger, "fp1").await;
        let found = ledger.find_by_fingerprint(&origin(), "fp1").await.unwrap();
        assert!(found.is_some());
    }

    #[tokio::test]
    async fn find_by_fingerprint_returns_none_for_unknown() {
        let ledger = InMemoryLedger::default();
        let found = ledger.find_by_fingerprint(&origin(), "nope").await.unwrap();
        assert!(found.is_none());
    }

    #[tokio::test]
    async fn find_by_token_hash_returns_wallet() {
        let ledger = InMemoryLedger::default();
        let wallet = mint_test_wallet(&ledger, "fp1").await;
        let found = ledger.find_by_token_hash(&wallet.token_hash).await.unwrap();
        assert!(found.is_some());
    }

    #[tokio::test]
    async fn debit_reduces_balance_atomically() {
        let ledger = InMemoryLedger::default();
        let wallet = mint_test_wallet(&ledger, "fp1").await;
        ledger.debit(wallet.id, 1000).await.unwrap();
        let updated = ledger.find_by_token_hash("hash1").await.unwrap().unwrap();
        assert_eq!(updated.balance_millicredits, 499_000);
    }

    #[tokio::test]
    async fn debit_can_go_slightly_negative() {
        let ledger = InMemoryLedger::default();
        let wallet = ledger
            .mint(&origin(), "fp1", "prod.500", 100, "hash1", "cipher1")
            .await
            .unwrap();
        ledger.debit(wallet.id, 200).await.unwrap();
        let updated = ledger.find_by_token_hash("hash1").await.unwrap().unwrap();
        assert_eq!(updated.balance_millicredits, -100);
    }

    #[tokio::test]
    async fn close_zeros_balance_and_sets_status() {
        let ledger = InMemoryLedger::default();
        let wallet = mint_test_wallet(&ledger, "fp1").await;
        ledger
            .close(wallet.id, WalletStatus::Refunded)
            .await
            .unwrap();
        let updated = ledger.find_by_token_hash("hash1").await.unwrap().unwrap();
        assert_eq!(updated.balance_millicredits, 0);
        assert_eq!(updated.status, WalletStatus::Refunded);
    }

    #[tokio::test]
    async fn record_notification_first_call_returns_true() {
        let ledger = InMemoryLedger::default();
        let is_new = ledger.record_notification("uuid-1").await.unwrap();
        assert!(is_new);
    }

    #[tokio::test]
    async fn record_notification_second_call_returns_false() {
        let ledger = InMemoryLedger::default();
        ledger.record_notification("uuid-1").await.unwrap();
        let is_new = ledger.record_notification("uuid-1").await.unwrap();
        assert!(!is_new);
    }
}
