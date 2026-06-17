//! Single-environment Apple JWS verifier.
//!
//! Backed by `app-store-server-library`'s `SignedDataVerifier`, which verifies
//! the x5c certificate chain against Apple Root CAs and checks bundle ID and
//! environment, avoiding network calls to Apple at runtime.

use crate::error::AppError;

use super::verifier::{
    AppleEnvironment, AppleVerifier, NotificationType, VerifiedNotification, VerifiedTransaction,
};

/// Verifier pinned to one Apple environment.
///
/// It rejects tokens from the other environment (`INVALID_ENVIRONMENT`). Compose
/// several behind a [`super::MultiEnvironmentVerifier`] to accept more than one.
pub struct AppStoreVerifier {
    verifier: app_store_server_library::signed_data_verifier::SignedDataVerifier,
    environment: AppleEnvironment,
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

        let environment = AppleEnvironment::parse(environment)?;
        let env = match environment {
            AppleEnvironment::Production => Environment::Production,
            AppleEnvironment::Sandbox => Environment::Sandbox,
        };

        let inner = app_store_server_library::signed_data_verifier::SignedDataVerifier::new(
            root_certs_der,
            env,
            bundle_id,
            app_apple_id,
        );

        Ok(Self {
            verifier: inner,
            environment,
        })
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
            environment: self.environment,
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
            environment: self.environment,
        })
    }
}
