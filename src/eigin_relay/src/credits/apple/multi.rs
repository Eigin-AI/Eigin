//! Multi-environment Apple JWS verifier.

use crate::error::AppError;

use super::verifier::{AppleVerifier, VerifiedNotification, VerifiedTransaction};

/// Accepts transactions and notifications from any of several pinned verifiers,
/// spanning both Apple environments and bundle IDs.
///
/// Verification is cryptographically enforced per verifier (each checks the
/// environment claim and the bundle ID), so trying each in turn and taking the
/// first that succeeds is safe — a token cannot pass a verifier pinned to the
/// wrong environment or bundle ID. This is Apple's recommended StoreKit 2 JWS
/// approach; there is no `verifyReceipt`-style 21007 fallback.
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

    /// A verifier pinned to one bundle ID and environment, like a real one, so we
    /// can test selection across a list spanning both dimensions. It accepts a
    /// token formatted as `"<bundle_id>|<environment>"` and rejects anything else,
    /// mirroring how a real verifier rejects the wrong bundle ID or environment.
    struct StubVerifier {
        bundle_id: &'static str,
        environment: AppleEnvironment,
    }

    impl StubVerifier {
        fn token(&self) -> String {
            format!("{}|{}", self.bundle_id, self.environment.as_str())
        }
    }

    impl AppleVerifier for StubVerifier {
        fn verify_transaction(&self, jws: &str) -> Result<VerifiedTransaction, AppError> {
            if jws == self.token() {
                Ok(VerifiedTransaction {
                    original_transaction_id: "tx".into(),
                    product_id: "p".into(),
                    environment: self.environment,
                })
            } else {
                Err(AppError::UnprocessableEntity(
                    "wrong bundle id or environment".into(),
                ))
            }
        }

        fn verify_notification(&self, _: &str) -> Result<VerifiedNotification, AppError> {
            Err(AppError::UnprocessableEntity("unused".into()))
        }
    }

    fn multi() -> MultiEnvironmentVerifier {
        MultiEnvironmentVerifier::new(vec![
            Box::new(StubVerifier {
                bundle_id: "ai.eigin.finch",
                environment: AppleEnvironment::Production,
            }),
            Box::new(StubVerifier {
                bundle_id: "ai.eigin.finch",
                environment: AppleEnvironment::Sandbox,
            }),
        ])
    }

    /// Mirrors a migration: one relay serving the legacy alpha and the new App
    /// Store release, each across both environments — the full bundle×env grid.
    fn multi_bundle() -> MultiEnvironmentVerifier {
        let bundles = ["com.42futures.carrel", "ai.eigin.finch"];
        let environments = [AppleEnvironment::Production, AppleEnvironment::Sandbox];
        MultiEnvironmentVerifier::new(
            bundles
                .iter()
                .flat_map(|&bundle_id| {
                    environments.iter().map(move |&environment| {
                        Box::new(StubVerifier {
                            bundle_id,
                            environment,
                        }) as Box<dyn AppleVerifier>
                    })
                })
                .collect(),
        )
    }

    #[test]
    fn selects_the_environment_that_verifies() {
        // A sandbox token fails the production verifier but is accepted by the
        // sandbox one, and the result carries the matching environment.
        let tx = multi()
            .verify_transaction("ai.eigin.finch|Sandbox")
            .unwrap();
        assert_eq!(tx.environment, AppleEnvironment::Sandbox);

        let tx = multi()
            .verify_transaction("ai.eigin.finch|Production")
            .unwrap();
        assert_eq!(tx.environment, AppleEnvironment::Production);
    }

    #[test]
    fn accepts_tokens_from_any_configured_bundle_id() {
        // Both the legacy alpha and the new release verify against the same relay,
        // in either environment — this is what keeps the alpha live during review.
        for token in [
            "com.42futures.carrel|Production",
            "com.42futures.carrel|Sandbox",
            "ai.eigin.finch|Production",
            "ai.eigin.finch|Sandbox",
        ] {
            assert!(
                multi_bundle().verify_transaction(token).is_ok(),
                "expected {token} to verify"
            );
        }
    }

    #[test]
    fn rejects_tokens_from_an_unconfigured_bundle_id() {
        // A bundle ID the relay was never told about is rejected, even in a valid
        // environment — verification is not a wildcard.
        assert!(
            multi_bundle()
                .verify_transaction("com.someone.else|Production")
                .is_err()
        );
    }

    #[test]
    fn rejects_when_no_verifier_accepts() {
        assert!(multi().verify_transaction("Garbage").is_err());
    }
}
