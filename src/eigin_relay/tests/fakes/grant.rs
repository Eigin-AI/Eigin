use eigin_relay::AppError;
use eigin_relay::credits::grant::{GrantVerifier, VerifiedGrant};

/// Configurable fake grant verifier for integration tests.
pub struct FakeGrantVerifier {
    result: Result<VerifiedGrant, String>,
}

impl FakeGrantVerifier {
    pub fn with_grant(issuer: &str, grant_id: &str, product_id: &str) -> Self {
        Self {
            result: Ok(VerifiedGrant {
                issuer: issuer.to_owned(),
                grant_id: grant_id.to_owned(),
                product_id: product_id.to_owned(),
            }),
        }
    }

    pub fn failing() -> Self {
        Self {
            result: Err("grant verification failed".into()),
        }
    }
}

impl GrantVerifier for FakeGrantVerifier {
    fn verify(&self, _token: &str) -> Result<VerifiedGrant, AppError> {
        self.result
            .as_ref()
            .cloned()
            .map_err(|e| AppError::UnprocessableEntity(e.clone()))
    }
}
