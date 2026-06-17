//! The Apple verification contract: the [`AppleVerifier`] trait and the value
//! types it produces. Implementations live alongside: a single-environment
//! verifier in `single.rs` and a multi-environment one in `multi.rs`.

use crate::error::AppError;

/// The Apple environment a transaction or notification was issued in.
///
/// TestFlight and App Review always operate in `Sandbox`; the live App Store
/// is `Production`. A single relay may accept both, scoping wallets by it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AppleEnvironment {
    Production,
    Sandbox,
}

impl AppleEnvironment {
    pub fn as_str(&self) -> &'static str {
        match self {
            AppleEnvironment::Production => "Production",
            AppleEnvironment::Sandbox => "Sandbox",
        }
    }

    /// Parse the value used by `APPLE_ENVIRONMENTS` and Apple's library.
    /// `LocalTesting` maps to `Sandbox`.
    pub fn parse(s: &str) -> Result<Self, String> {
        match s.trim() {
            "Production" => Ok(AppleEnvironment::Production),
            "Sandbox" | "LocalTesting" => Ok(AppleEnvironment::Sandbox),
            other => Err(format!("unknown Apple environment: {other}")),
        }
    }
}

/// The extracted fields we need from a verified StoreKit 2 transaction.
#[derive(Debug, Clone)]
pub struct VerifiedTransaction {
    /// Apple's stable identifier for the original purchase which we use as the fingerprint basis.
    pub original_transaction_id: String,
    /// The product identifier which we map to a credit tier.
    pub product_id: String,
    /// The environment whose verifier accepted this transaction.
    pub environment: AppleEnvironment,
}

/// The notification type from App Store Server Notifications V2.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum NotificationType {
    /// The purchase was refunded, so we need to close the credit wallet.
    Refund,
    /// Any other notification type. We don't take action on these.
    Other(String),
}

/// The extracted fields we need from a verified App Store Server Notification.
#[derive(Debug, Clone)]
pub struct VerifiedNotification {
    pub notification_uuid: String,
    /// Type of notification from Apple.
    pub notification_type: NotificationType,
    /// Present for refund notifications.
    pub original_transaction_id: Option<String>,
    /// The environment whose verifier accepted this notification.
    pub environment: AppleEnvironment,
}

/// Verifies Apple JWS payloads.
pub trait AppleVerifier: Send + Sync {
    /// Verify a StoreKit 2 `Transaction.jwsRepresentation` and extract the fields we need.
    fn verify_transaction(&self, jws: &str) -> Result<VerifiedTransaction, AppError>;

    /// Verify a signed App Store Server Notification payload and extract fields.
    fn verify_notification(&self, signed_payload: &str) -> Result<VerifiedNotification, AppError>;
}

/// Load DER-encoded Apple Root CA certs from a directory.
/// Returns an empty vec if the directory doesn't exist (dev mode).
pub fn load_root_certs(dir: &str) -> Vec<Vec<u8>> {
    let path = std::path::Path::new(dir);
    if !path.exists() {
        return Vec::new();
    }
    let mut certs = Vec::new();
    if let Ok(entries) = std::fs::read_dir(path) {
        for entry in entries.flatten() {
            let p = entry.path();
            if p.extension().and_then(|e| e.to_str()) == Some("cer") {
                if let Ok(bytes) = std::fs::read(&p) {
                    certs.push(bytes);
                }
            }
        }
    }
    certs
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_maps_local_testing_to_sandbox() {
        assert_eq!(
            AppleEnvironment::parse("LocalTesting").unwrap(),
            AppleEnvironment::Sandbox
        );
        assert!(AppleEnvironment::parse("Nope").is_err());
    }
}
