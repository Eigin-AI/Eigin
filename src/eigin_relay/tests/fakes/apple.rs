use eigin_relay::AppError;
use eigin_relay::credits::apple::{
    AppleEnvironment, AppleVerifier, NotificationType, VerifiedNotification, VerifiedTransaction,
};

/// Configurable fake Apple verifier for integration tests.
pub struct FakeVerifier {
    pub transaction_result: Result<VerifiedTransaction, String>,
    pub notification_result: Result<VerifiedNotification, String>,
}

impl FakeVerifier {
    pub fn with_transaction(original_transaction_id: &str, product_id: &str) -> Self {
        Self::with_transaction_env(
            original_transaction_id,
            product_id,
            AppleEnvironment::Production,
        )
    }

    pub fn with_transaction_env(
        original_transaction_id: &str,
        product_id: &str,
        environment: AppleEnvironment,
    ) -> Self {
        Self {
            transaction_result: Ok(VerifiedTransaction {
                original_transaction_id: original_transaction_id.to_owned(),
                product_id: product_id.to_owned(),
                environment,
            }),
            notification_result: Ok(VerifiedNotification {
                notification_uuid: "test-uuid".to_owned(),
                notification_type: NotificationType::Other("INITIAL_BUY".into()),
                original_transaction_id: None,
                environment,
                signed_date: Some(time::OffsetDateTime::now_utc()),
            }),
        }
    }

    pub fn with_refund_notification(
        original_transaction_id: &str,
        notification_uuid: &str,
    ) -> Self {
        Self::with_refund_notification_env(
            original_transaction_id,
            notification_uuid,
            AppleEnvironment::Production,
        )
    }

    pub fn with_refund_notification_env(
        original_transaction_id: &str,
        notification_uuid: &str,
        environment: AppleEnvironment,
    ) -> Self {
        Self {
            transaction_result: Err("no transaction in refund verifier".into()),
            notification_result: Ok(VerifiedNotification {
                notification_uuid: notification_uuid.to_owned(),
                notification_type: NotificationType::Refund,
                original_transaction_id: Some(original_transaction_id.to_owned()),
                environment,
                signed_date: Some(time::OffsetDateTime::now_utc()),
            }),
        }
    }

    /// Override the notification's `signed_date`, for testing the webhook's
    /// freshness window. No-op if the fake's notification_result is `Err`.
    pub fn signed_at(mut self, signed_date: time::OffsetDateTime) -> Self {
        if let Ok(n) = self.notification_result.as_mut() {
            n.signed_date = Some(signed_date);
        }
        self
    }

    /// Drop `signed_date` entirely, for testing the fail-closed path.
    pub fn without_signed_date(mut self) -> Self {
        if let Ok(n) = self.notification_result.as_mut() {
            n.signed_date = None;
        }
        self
    }

    pub fn failing() -> Self {
        Self {
            transaction_result: Err("verification failed".into()),
            notification_result: Err("verification failed".into()),
        }
    }
}

impl AppleVerifier for FakeVerifier {
    fn verify_transaction(&self, _jws: &str) -> Result<VerifiedTransaction, AppError> {
        self.transaction_result
            .as_ref()
            .cloned()
            .map_err(|e| AppError::UnprocessableEntity(e.clone()))
    }

    fn verify_notification(&self, _signed_payload: &str) -> Result<VerifiedNotification, AppError> {
        self.notification_result
            .as_ref()
            .cloned()
            .map_err(|e| AppError::UnprocessableEntity(e.clone()))
    }
}
