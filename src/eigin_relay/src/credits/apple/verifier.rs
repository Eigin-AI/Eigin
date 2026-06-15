//! Apple JWS verification for StoreKit 2 transactions and App Store Server Notifications V2.
//!
//! It uses `app-store-server-library`'s `SignedDataVerifier`,
//! which verifies the x5c certificate chain against Apple Root CAs and checks
//! bundle ID and environment, avoiding network calls to Apple at runtime.

use crate::error::AppError;

/// The extracted fields we need from a verified StoreKit 2 transaction.
#[derive(Debug, Clone)]
pub struct VerifiedTransaction {
    /// Apple's stable identifier for the original purchase which we use as the fingerprint basis.
    pub original_transaction_id: String,
    /// The product identifier which we map to a credit tier.
    pub product_id: String,
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
}

/// Verifies Apple JWS payloads.
pub trait AppleVerifier: Send + Sync {
    /// Verify a StoreKit 2 `Transaction.jwsRepresentation` and extract the fields we need.
    fn verify_transaction(&self, jws: &str) -> Result<VerifiedTransaction, AppError>;

    /// Verify a signed App Store Server Notification payload and extract fields.
    fn verify_notification(&self, signed_payload: &str) -> Result<VerifiedNotification, AppError>;
}

/// Production implementation backed by `app-store-server-library`.
pub struct AppStoreVerifier {
    verifier: app_store_server_library::signed_data_verifier::SignedDataVerifier,
}

impl AppStoreVerifier {
    /// Construct the verifier.
    ///
    /// - `root_certs_der`: DER-encoded Apple Root CA certificate bytes. Load these from
    ///   `config/apple/` at startup. They are public certs committed to the repo.
    /// - `bundle_id`: The app's bundle ID, e.g. `"ai.eigin.app"`.
    /// - `app_apple_id`: Required in production; `None` is accepted in sandbox.
    /// - `environment`: `"Production"` or `"Sandbox"`.
    pub fn new(
        root_certs_der: Vec<Vec<u8>>,
        bundle_id: String,
        app_apple_id: Option<i64>,
        environment: &str,
    ) -> Result<Self, String> {
        use app_store_server_library::primitives::environment::Environment;

        let env = match environment {
            "Production" => Environment::Production,
            "Sandbox" | "LocalTesting" => Environment::Sandbox,
            other => return Err(format!("unknown APPLE_ENVIRONMENT: {other}")),
        };

        let inner = app_store_server_library::signed_data_verifier::SignedDataVerifier::new(
            root_certs_der,
            env,
            bundle_id,
            app_apple_id,
        );

        Ok(Self { verifier: inner })
    }
}

impl AppleVerifier for AppStoreVerifier {
    fn verify_transaction(&self, jws: &str) -> Result<VerifiedTransaction, AppError> {
        let payload = self
            .verifier
            .verify_and_decode_signed_transaction(jws)
            .map_err(|e| {
                AppError::UnprocessableEntity(format!("JWS verification failed: {e:?}"))
            })?;

        let original_transaction_id = payload
            .original_transaction_id
            .ok_or_else(|| AppError::UnprocessableEntity("missing originalTransactionId".into()))?;

        let product_id = payload
            .product_id
            .ok_or_else(|| AppError::UnprocessableEntity("missing productId".into()))?;

        Ok(VerifiedTransaction {
            original_transaction_id,
            product_id,
        })
    }

    fn verify_notification(&self, signed_payload: &str) -> Result<VerifiedNotification, AppError> {
        use app_store_server_library::primitives::notification_type_v2::NotificationTypeV2;

        let payload = self
            .verifier
            .verify_and_decode_notification(signed_payload)
            .map_err(|e| {
                AppError::UnprocessableEntity(format!("notification verification failed: {e:?}"))
            })?;

        let notification_uuid = payload.notification_uuid;

        let notification_type = match payload.notification_type {
            NotificationTypeV2::Refund => NotificationType::Refund,
            other => NotificationType::Other(format!("{other:?}")),
        };

        // Extract originalTransactionId from the embedded signed transaction if present.
        let original_transaction_id = payload
            .data
            .as_ref()
            .and_then(|d| d.signed_transaction_info.as_deref())
            .and_then(|jws| {
                self.verifier
                    .verify_and_decode_signed_transaction(jws)
                    .ok()
                    .and_then(|t| t.original_transaction_id)
            });

        Ok(VerifiedNotification {
            notification_uuid,
            notification_type,
            original_transaction_id,
        })
    }
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
