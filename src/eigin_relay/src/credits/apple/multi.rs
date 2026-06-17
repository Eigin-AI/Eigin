//! Multi-environment Apple JWS verifier.

use crate::error::AppError;

use super::verifier::{AppleVerifier, VerifiedNotification, VerifiedTransaction};

/// Accepts transactions and notifications from any of several Apple environments.
///
/// Verification is cryptographically enforced per environment (each underlying
/// verifier checks the environment claim), so trying each in turn and taking the
/// first that succeeds is safe — a token cannot pass a verifier for the wrong
/// environment. This is Apple's recommended StoreKit 2 JWS approach; there is no
/// `verifyReceipt`-style 21007 fallback.
pub struct MultiEnvironmentVerifier {
    verifiers: Vec<Box<dyn AppleVerifier>>,
}

impl MultiEnvironmentVerifier {
    /// Construct from a non-empty list of single-environment verifiers.
    pub fn new(verifiers: Vec<Box<dyn AppleVerifier>>) -> Self {
        debug_assert!(!verifiers.is_empty(), "at least one verifier is required");
        Self { verifiers }
    }
}

impl AppleVerifier for MultiEnvironmentVerifier {
    fn verify_transaction(&self, jws: &str) -> Result<VerifiedTransaction, AppError> {
        let mut last_err = None;
        for verifier in &self.verifiers {
            match verifier.verify_transaction(jws) {
                Ok(tx) => return Ok(tx),
                Err(e) => last_err = Some(e),
            }
        }
        Err(last_err.unwrap_or_else(|| {
            AppError::UnprocessableEntity("no Apple verifier configured".into())
        }))
    }

    fn verify_notification(&self, signed_payload: &str) -> Result<VerifiedNotification, AppError> {
        let mut last_err = None;
        for verifier in &self.verifiers {
            match verifier.verify_notification(signed_payload) {
                Ok(n) => return Ok(n),
                Err(e) => last_err = Some(e),
            }
        }
        Err(last_err.unwrap_or_else(|| {
            AppError::UnprocessableEntity("no Apple verifier configured".into())
        }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::credits::apple::AppleEnvironment;

    /// A verifier that accepts only its own environment, like a real one keyed
    /// to a single Apple environment, so we can test selection across a list.
    struct StubVerifier {
        environment: AppleEnvironment,
    }

    impl AppleVerifier for StubVerifier {
        fn verify_transaction(&self, jws: &str) -> Result<VerifiedTransaction, AppError> {
            if jws == self.environment.as_str() {
                Ok(VerifiedTransaction {
                    original_transaction_id: "tx".into(),
                    product_id: "p".into(),
                    environment: self.environment,
                })
            } else {
                Err(AppError::UnprocessableEntity("wrong environment".into()))
            }
        }

        fn verify_notification(&self, _: &str) -> Result<VerifiedNotification, AppError> {
            Err(AppError::UnprocessableEntity("unused".into()))
        }
    }

    fn multi() -> MultiEnvironmentVerifier {
        MultiEnvironmentVerifier::new(vec![
            Box::new(StubVerifier {
                environment: AppleEnvironment::Production,
            }),
            Box::new(StubVerifier {
                environment: AppleEnvironment::Sandbox,
            }),
        ])
    }

    #[test]
    fn selects_the_environment_that_verifies() {
        // A sandbox token fails the production verifier but is accepted by the
        // sandbox one, and the result carries the matching environment.
        let tx = multi().verify_transaction("Sandbox").unwrap();
        assert_eq!(tx.environment, AppleEnvironment::Sandbox);

        let tx = multi().verify_transaction("Production").unwrap();
        assert_eq!(tx.environment, AppleEnvironment::Production);
    }

    #[test]
    fn rejects_when_no_verifier_accepts() {
        assert!(multi().verify_transaction("Garbage").is_err());
    }
}
