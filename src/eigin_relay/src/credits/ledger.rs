//! Credit ledger trait and shared types.
//!
//! The ledger is the source of truth for wallet balances. All mutations are
//! designed to be atomic — particularly debits, which must be a single
//! `UPDATE ... SET balance = balance - n` with no read-modify-write.

use async_trait::async_trait;
use uuid::Uuid;

/// The origin of an entitlement — which store or system minted the wallet.
///
/// Origin-scoping prevents fingerprint collisions across stores that may
/// independently issue IDs using the same scheme.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WalletOrigin {
    /// Credits granted from an Apple App Store purchase in the Production environment
    AppleAppStore,
    /// Credits granted from an Apple Sandbox purchase (TestFlight / App Review).
    AppleAppStoreSandbox,
    /// Credits granted directly by a trusted issuer (not via a store)
    Grant,
}

impl WalletOrigin {
    pub fn as_str(&self) -> &'static str {
        match self {
            WalletOrigin::AppleAppStore => "apple_app_store",
            WalletOrigin::AppleAppStoreSandbox => "apple_app_store_sandbox",
            WalletOrigin::Grant => "grant",
        }
    }
}

impl std::fmt::Display for WalletOrigin {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

impl TryFrom<&str> for WalletOrigin {
    type Error = LedgerError;

    fn try_from(s: &str) -> Result<Self, Self::Error> {
        match s {
            "apple_app_store" => Ok(WalletOrigin::AppleAppStore),
            "apple_app_store_sandbox" => Ok(WalletOrigin::AppleAppStoreSandbox),
            "grant" => Ok(WalletOrigin::Grant),
            other => Err(LedgerError::Internal(format!(
                "unknown wallet origin: {other}"
            ))),
        }
    }
}

/// The lifecycle status of a wallet.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WalletStatus {
    Active,
    Refunded,
    Closed,
}

impl WalletStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            WalletStatus::Active => "active",
            WalletStatus::Refunded => "refunded",
            WalletStatus::Closed => "closed",
        }
    }
}

impl TryFrom<&str> for WalletStatus {
    type Error = LedgerError;

    fn try_from(s: &str) -> Result<Self, Self::Error> {
        match s {
            "active" => Ok(WalletStatus::Active),
            "refunded" => Ok(WalletStatus::Refunded),
            "closed" => Ok(WalletStatus::Closed),
            other => Err(LedgerError::Internal(format!(
                "unknown wallet status: {other}"
            ))),
        }
    }
}

/// A single credit wallet.
#[derive(Debug, Clone)]
pub struct Wallet {
    pub id: Uuid,
    /// SHA-256 hex of the bearer token, usable for lookup.
    pub token_hash: String,
    /// AEAD-encrypted token for restore.
    pub token_ciphertext: String,
    /// Fingerprint of the key that encrypted `token_ciphertext` (see `token::fingerprint`).
    pub key_fp: String,
    /// How the wallet originated, like from an IAP transaction.
    pub origin: WalletOrigin,
    /// SHA-256 hex of the origin's transaction identifier.
    pub fingerprint: String,
    /// The ID of the product that originated this wallet.
    pub product_id: String,
    /// Initial credit balance.
    pub initial_millicredits: i64,
    /// Current credit balance. May go slightly negative after a final over-run request.
    pub balance_millicredits: i64,
    /// Current wallet status.
    pub status: WalletStatus,
}

impl Wallet {
    /// Whole credits remaining, clamped to zero.
    /// Negative balances (from the over-run allowance) are not exposed to callers —
    /// the internal millicredit value is used for admit checks and debiting.
    pub fn credits(&self) -> i64 {
        (self.balance_millicredits / 1000).max(0)
    }
}

/// The inputs needed to mint a new wallet, grouped so `mint` stays a single-argument call.
pub struct NewWallet<'a> {
    pub origin: &'a WalletOrigin,
    /// SHA-256 hex of the origin's transaction identifier, scoped by origin.
    pub fingerprint: &'a str,
    pub product_id: &'a str,
    pub millicredits: i64,
    /// SHA-256 hex of the bearer token, used for lookup.
    pub token_hash: &'a str,
    /// AEAD-encrypted token for restore.
    pub token_ciphertext: &'a str,
    /// Fingerprint of the key that encrypted `token_ciphertext` (see `token::fingerprint`).
    pub key_fp: &'a str,
}

/// Errors returned by the credit ledger.
#[derive(Debug, thiserror::Error)]
pub enum LedgerError {
    #[error("wallet with this fingerprint already exists")]
    DuplicateFingerprint,

    #[error("wallet not found")]
    NotFound,

    #[error("insufficient balance to reserve the estimated cost")]
    InsufficientBalance,

    #[error("ledger error: {0}")]
    Internal(String),
}

/// The credit ledger. All mutations must be atomic — single-statement and
/// conflict-checked, never read-modify-write across an await.
///
/// - `mint` is idempotent on `(origin, fingerprint)` -> `DuplicateFingerprint`.
/// - `reserve` holds an estimated cost before serving, refusing on overdraft so
///   concurrent holds can't collectively push the balance negative. Reconciled to
///   actual usage by `debit` at settle.
/// - `debit` is a signed settlement delta (`actual - reserved`); may drive the
///   balance slightly negative when usage exceeds the reservation.
/// - `record_notification` is insert-or-ignore for concurrent safety.
#[async_trait]
pub trait CreditLedger: Send + Sync {
    /// Create a new wallet. Returns `DuplicateFingerprint` if (origin, fingerprint)
    /// already exists.
    async fn mint(&self, new: NewWallet<'_>) -> Result<Wallet, LedgerError>;

    /// Look up a wallet by (origin, fingerprint). Returns `None` if not found.
    async fn find_by_fingerprint(
        &self,
        origin: &WalletOrigin,
        fingerprint: &str,
    ) -> Result<Option<Wallet>, LedgerError>;

    /// Look up a wallet by the SHA-256 hash of its bearer token.
    async fn find_by_token_hash(&self, token_hash: &str) -> Result<Option<Wallet>, LedgerError>;

    /// Atomically debit millicredits from a wallet. The amount is signed — settlement
    /// passes `actual - reserved` (positive charges, negative refunds). The balance
    /// may go negative when actual usage exceeds the prior reservation.
    async fn debit(&self, wallet_id: Uuid, millicredits: i64) -> Result<(), LedgerError>;

    /// Reserve millicredits as an authorization hold before serving inference.
    /// Admits only if the balance would remain non-negative, so concurrent
    /// reservations against the same balance can't collectively overdraw. Returns
    /// [`LedgerError::InsufficientBalance`] when the hold would overdraw. The held
    /// amount is reconciled to actual usage by [`debit`] when the response settles.
    async fn reserve(&self, wallet_id: Uuid, millicredits: i64) -> Result<(), LedgerError>;

    /// Zero the balance and mark a wallet as refunded or closed.
    async fn close(&self, wallet_id: Uuid, status: WalletStatus) -> Result<(), LedgerError>;

    /// Record a processed notification UUID for idempotency.
    /// Returns `true` if newly recorded, `false` if already seen.
    async fn record_notification(&self, notification_uuid: &str) -> Result<bool, LedgerError>;
}

#[cfg(test)]
mod tests {
    use super::*;

    fn wallet_with_balance(balance_millicredits: i64) -> Wallet {
        Wallet {
            id: uuid::Uuid::new_v4(),
            token_hash: String::new(),
            token_ciphertext: String::new(),
            key_fp: String::new(),
            origin: WalletOrigin::AppleAppStore,
            fingerprint: String::new(),
            product_id: String::new(),
            initial_millicredits: 0,
            balance_millicredits,
            status: WalletStatus::Active,
        }
    }

    #[test]
    fn credits_floors_positive_balance() {
        assert_eq!(wallet_with_balance(1500).credits(), 1);
        assert_eq!(wallet_with_balance(1000).credits(), 1);
        assert_eq!(wallet_with_balance(999).credits(), 0);
    }

    #[test]
    fn credits_clamps_negative_balance_to_zero() {
        assert_eq!(wallet_with_balance(-1).credits(), 0);
        assert_eq!(wallet_with_balance(-999).credits(), 0);
        assert_eq!(wallet_with_balance(-1000).credits(), 0);
        assert_eq!(wallet_with_balance(-1001).credits(), 0);
    }

    #[test]
    fn credits_zero_balance_is_zero() {
        assert_eq!(wallet_with_balance(0).credits(), 0);
    }
}
