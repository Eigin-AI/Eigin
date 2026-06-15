//! Ed25519 JWT verification for credit grants.
//!
//! A grant is a JWT (`alg: EdDSA`) signed offline by a trusted issuer who holds the
//! private key. The relay holds only the public key and verifies; it cannot forge
//! grants. The token carries the registered claims `iss`, `jti`, `exp` plus a custom
//! `product_id` that maps to a credit tier.
//!
//! `jti` is the unique grant identifier and `iss` the issuer; together they form the
//! wallet fingerprint, so re-redeeming a grant restores the same wallet and two issuers
//! reusing a `jti` cannot collide.

use jsonwebtoken::{Algorithm, DecodingKey, Validation, decode};
use serde::Deserialize;

use crate::error::AppError;

/// The fields we extract from a verified grant token.
#[derive(Debug, Clone)]
pub struct VerifiedGrant {
    /// The issuer that signed the grant (`iss`).
    pub issuer: String,
    /// The unique grant identifier (`jti`), used as the fingerprint basis.
    pub grant_id: String,
    /// The product identifier, mapped to a credit tier.
    pub product_id: String,
}

/// Verifies signed grant tokens.
pub trait GrantVerifier: Send + Sync {
    /// Verify a grant JWT and extract the fields we need.
    fn verify(&self, token: &str) -> Result<VerifiedGrant, AppError>;
}

/// The grant JWT claim set.
#[derive(Debug, Deserialize)]
struct Claims {
    iss: String,
    jti: String,
    product_id: String,
}

/// Production verifier backed by an Ed25519 public key.
pub struct Ed25519GrantVerifier {
    decoding_key: DecodingKey,
    validation: Validation,
}

impl Ed25519GrantVerifier {
    /// Construct from a PEM-encoded Ed25519 public key (SPKI, `BEGIN PUBLIC KEY`).
    ///
    /// Only tokens issued by `issuer` and signed with `EdDSA` are accepted; `exp`, `iss`,
    /// and `jti` are required. Pinning the algorithm guards against the `alg: none` and
    /// algorithm-confusion attacks.
    pub fn from_public_pem(pem: &str, issuer: &str) -> Result<Self, String> {
        let decoding_key = DecodingKey::from_ed_pem(pem.as_bytes())
            .map_err(|e| format!("invalid grant public key: {e}"))?;

        let mut validation = Validation::new(Algorithm::EdDSA);
        validation.set_issuer(&[issuer]);
        validation.set_required_spec_claims(&["exp", "iss", "jti"]);
        validation.validate_exp = true;

        Ok(Self {
            decoding_key,
            validation,
        })
    }
}

impl GrantVerifier for Ed25519GrantVerifier {
    fn verify(&self, token: &str) -> Result<VerifiedGrant, AppError> {
        let data = decode::<Claims>(token, &self.decoding_key, &self.validation).map_err(|e| {
            AppError::UnprocessableEntity(format!("grant verification failed: {e}"))
        })?;

        Ok(VerifiedGrant {
            issuer: data.claims.iss,
            grant_id: data.claims.jti,
            product_id: data.claims.product_id,
        })
    }
}

/// A verifier that rejects all grants. Installed when no grant public key is configured
/// so grant redemption fails closed rather than panicking at startup.
pub struct RejectingGrantVerifier;

impl GrantVerifier for RejectingGrantVerifier {
    fn verify(&self, _token: &str) -> Result<VerifiedGrant, AppError> {
        Err(AppError::UnprocessableEntity(
            "grant redemption is not configured".into(),
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ed25519_dalek::SigningKey;
    use ed25519_dalek::pkcs8::EncodePrivateKey;
    use ed25519_dalek::pkcs8::spki::EncodePublicKey;
    use ed25519_dalek::pkcs8::spki::der::pem::LineEnding;
    use jsonwebtoken::{EncodingKey, Header, encode, get_current_timestamp};
    use serde::Serialize;

    #[derive(Serialize)]
    struct SignClaims {
        iss: String,
        jti: String,
        exp: u64,
        product_id: String,
    }

    /// A signer plus the PEM-encoded public key it verifies against.
    struct TestKeys {
        signing_pem: String,
        public_pem: String,
    }

    fn keys() -> TestKeys {
        let signing = SigningKey::generate(&mut rand::rngs::OsRng);
        let signing_pem = signing.to_pkcs8_pem(LineEnding::LF).unwrap().to_string();
        let public_pem = signing
            .verifying_key()
            .to_public_key_pem(LineEnding::LF)
            .unwrap();
        TestKeys {
            signing_pem,
            public_pem,
        }
    }

    fn sign(signing_pem: &str, claims: &SignClaims) -> String {
        let key = EncodingKey::from_ed_pem(signing_pem.as_bytes()).unwrap();
        encode(&Header::new(Algorithm::EdDSA), claims, &key).unwrap()
    }

    fn valid_claims() -> SignClaims {
        SignClaims {
            iss: "eigin".into(),
            jti: "grant-001".into(),
            exp: get_current_timestamp() + 3600,
            product_id: "eigin.credits.v1.grant.500".into(),
        }
    }

    #[test]
    fn verifies_and_extracts_a_valid_grant() {
        let k = keys();
        let token = sign(&k.signing_pem, &valid_claims());
        let verifier = Ed25519GrantVerifier::from_public_pem(&k.public_pem, "eigin").unwrap();

        let grant = verifier.verify(&token).unwrap();
        assert_eq!(grant.issuer, "eigin");
        assert_eq!(grant.grant_id, "grant-001");
        assert_eq!(grant.product_id, "eigin.credits.v1.grant.500");
    }

    #[test]
    fn rejects_a_token_signed_by_a_different_key() {
        let signer = keys();
        let other = keys();
        let token = sign(&signer.signing_pem, &valid_claims());
        let verifier = Ed25519GrantVerifier::from_public_pem(&other.public_pem, "eigin").unwrap();

        assert!(verifier.verify(&token).is_err());
    }

    #[test]
    fn rejects_a_tampered_token() {
        let k = keys();
        let token = sign(&k.signing_pem, &valid_claims());
        // Flip the last character of the signature segment.
        let mut tampered = token.clone();
        let last = tampered.pop().unwrap();
        tampered.push(if last == 'a' { 'b' } else { 'a' });
        let verifier = Ed25519GrantVerifier::from_public_pem(&k.public_pem, "eigin").unwrap();

        assert!(verifier.verify(&tampered).is_err());
    }

    #[test]
    fn rejects_an_expired_grant() {
        let k = keys();
        // Well past the default 60s clock-skew leeway.
        let claims = SignClaims {
            exp: get_current_timestamp() - 3600,
            ..valid_claims()
        };
        let token = sign(&k.signing_pem, &claims);
        let verifier = Ed25519GrantVerifier::from_public_pem(&k.public_pem, "eigin").unwrap();

        assert!(verifier.verify(&token).is_err());
    }

    #[test]
    fn rejects_a_grant_from_an_unexpected_issuer() {
        let k = keys();
        let claims = SignClaims {
            iss: "attacker".into(),
            ..valid_claims()
        };
        let token = sign(&k.signing_pem, &claims);
        let verifier = Ed25519GrantVerifier::from_public_pem(&k.public_pem, "eigin").unwrap();

        assert!(verifier.verify(&token).is_err());
    }

    #[test]
    fn rejects_a_grant_missing_jti() {
        #[derive(Serialize)]
        struct NoJti {
            iss: String,
            exp: u64,
            product_id: String,
        }
        let k = keys();
        let key = EncodingKey::from_ed_pem(k.signing_pem.as_bytes()).unwrap();
        let token = encode(
            &Header::new(Algorithm::EdDSA),
            &NoJti {
                iss: "eigin".into(),
                exp: get_current_timestamp() + 3600,
                product_id: "eigin.credits.v1.grant.500".into(),
            },
            &key,
        )
        .unwrap();
        let verifier = Ed25519GrantVerifier::from_public_pem(&k.public_pem, "eigin").unwrap();

        assert!(verifier.verify(&token).is_err());
    }
}
