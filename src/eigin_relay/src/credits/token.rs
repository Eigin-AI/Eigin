//! Credit token generation, hashing, and AEAD encryption for at-rest storage.
//!
//! Tokens use the `eict_` prefix ("Eigin credit token") to make them identifiable
//! in logs and detectable by secret scanners. The rest is 32 random bytes encoded
//! as base64url (no padding), giving ~256 bits of entropy.
//!
//! Tokens are stored in the database encrypted (ChaCha20-Poly1305) so that redeem
//! can return the same token on restore without storing it in plaintext.

use base64::{
    Engine,
    engine::general_purpose::{STANDARD, URL_SAFE, URL_SAFE_NO_PAD},
};
use chacha20poly1305::aead::{Aead, KeyInit};
use chacha20poly1305::{ChaCha20Poly1305, Key, Nonce};
use rand::RngCore;
use sha2::{Digest, Sha256};

use crate::error::AppError;

/// A freshly-generated credit token string (e.g. `eict_abc123...`).
pub struct CreditToken(pub String);

/// Generate a new cryptographically-random credit token.
pub fn generate() -> CreditToken {
    let mut bytes = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut bytes);
    CreditToken(format!("eict_{}", URL_SAFE_NO_PAD.encode(bytes)))
}

/// Compute the SHA-256 hex digest of a token string. Used as the database lookup key.
pub fn hash(token: &str) -> String {
    let digest = Sha256::digest(token.as_bytes());
    hex::encode(digest)
}

/// Derive a 96-bit nonce deterministically from the token hash.
///
/// ChaCha20-Poly1305 requires nonces to be unique per (plaintext, key) pair, not secret.
/// Tokens are 256-bit random values, so each token is unique with overwhelming probability.
/// The nonce uniqueness requirement is therefore satisfied without storing it separately.
/// A random/counter-based nonce would be equally valid, but doesn't add security benefit here
/// since the plaintext is already unique.
fn nonce_from_hash(token_hash: &str) -> Nonce {
    let digest = Sha256::digest(token_hash.as_bytes());
    Nonce::clone_from_slice(&digest[..12])
}

/// Encrypt a token for at-rest storage. Returns base64url-encoded ciphertext.
///
/// `encryption_key` must be exactly 32 raw bytes .
pub fn encrypt(
    token: &str,
    token_hash: &str,
    encryption_key: &[u8; 32],
) -> Result<String, AppError> {
    let cipher = ChaCha20Poly1305::new(Key::from_slice(encryption_key));
    let nonce = nonce_from_hash(token_hash);
    let ciphertext = cipher
        .encrypt(&nonce, token.as_bytes())
        .map_err(|e| AppError::Internal(format!("token encryption failed: {e}")))?;
    Ok(URL_SAFE_NO_PAD.encode(ciphertext))
}

/// Decrypt a token previously encrypted by [`encrypt`]. Returns the original token string.
///
/// `encryption_key` must be exactly 32 raw bytes.
pub fn decrypt(
    ciphertext_b64: &str,
    token_hash: &str,
    encryption_key: &[u8; 32],
) -> Result<String, AppError> {
    let ciphertext = URL_SAFE_NO_PAD.decode(ciphertext_b64).map_err(|e| {
        AppError::Internal(format!("token decryption: invalid ciphertext base64: {e}"))
    })?;
    let cipher = ChaCha20Poly1305::new(Key::from_slice(encryption_key));
    let nonce = nonce_from_hash(token_hash);
    let plaintext = cipher
        .decrypt(&nonce, ciphertext.as_slice())
        .map_err(|_| AppError::Internal("token decryption failed".into()))?;
    String::from_utf8(plaintext)
        .map_err(|e| AppError::Internal(format!("token decryption: invalid utf8: {e}")))
}

/// Parse a 32-byte AEAD key from a base64-encoded string.
///
/// Accepts standard base64, base64url, and both padded and unpadded variants.
pub fn parse_encryption_key(b64: &str) -> Result<[u8; 32], String> {
    let bytes = URL_SAFE_NO_PAD
        .decode(b64)
        .or_else(|_| URL_SAFE.decode(b64))
        .or_else(|_| STANDARD.decode(b64))
        .map_err(|e| format!("token encryption key was invalid base64: {e}"))?;
    bytes
        .try_into()
        .map_err(|_| "token encryption key must be exactly 32 bytes".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_key() -> [u8; 32] {
        [0x42u8; 32]
    }

    #[test]
    fn generated_token_has_prefix() {
        let token = generate();
        assert!(
            token.0.starts_with("eict_"),
            "token must start with eict_: {}",
            token.0
        );
    }

    #[test]
    fn generated_tokens_are_unique() {
        let a = generate();
        let b = generate();
        assert_ne!(a.0, b.0);
    }

    #[test]
    fn generated_token_has_sufficient_length() {
        // "eict_" + 43 chars of base64url (32 bytes)
        let token = generate();
        assert!(token.0.len() >= 48, "token too short: {}", token.0.len());
    }

    #[test]
    fn hash_is_deterministic() {
        let token = "eict_test";
        assert_eq!(hash(token), hash(token));
    }

    #[test]
    fn different_tokens_have_different_hashes() {
        assert_ne!(hash("eict_aaa"), hash("eict_bbb"));
    }

    #[test]
    fn encrypt_decrypt_roundtrip() {
        let key = test_key();
        let token = "eict_sometesttoken";
        let token_hash = hash(token);
        let ciphertext = encrypt(token, &token_hash, &key).unwrap();
        let recovered = decrypt(&ciphertext, &token_hash, &key).unwrap();
        assert_eq!(recovered, token);
    }

    #[test]
    fn decrypt_with_wrong_key_fails() {
        let key = test_key();
        let wrong_key = [0x99u8; 32];
        let token = "eict_sometesttoken";
        let token_hash = hash(token);
        let ciphertext = encrypt(token, &token_hash, &key).unwrap();
        assert!(decrypt(&ciphertext, &token_hash, &wrong_key).is_err());
    }

    #[test]
    fn parse_encryption_key_valid() {
        // 32 zero bytes base64url-encoded
        let encoded = URL_SAFE_NO_PAD.encode([0u8; 32]);
        let key = parse_encryption_key(&encoded).unwrap();
        assert_eq!(key, [0u8; 32]);
    }

    #[test]
    fn parse_encryption_key_wrong_length() {
        let encoded = URL_SAFE_NO_PAD.encode([0u8; 16]);
        assert!(parse_encryption_key(&encoded).is_err());
    }

    #[test]
    fn tampered_ciphertext_is_rejected() {
        let key = test_key();
        let token = "eict_sometesttoken";
        let token_hash = hash(token);
        let ciphertext_b64 = encrypt(token, &token_hash, &key).unwrap();
        let mut ciphertext = URL_SAFE_NO_PAD.decode(&ciphertext_b64).unwrap();
        ciphertext[0] ^= 0xff;
        let tampered = URL_SAFE_NO_PAD.encode(&ciphertext);
        assert!(decrypt(&tampered, &token_hash, &key).is_err());
    }

    #[test]
    fn different_tokens_produce_different_ciphertexts() {
        let key = test_key();
        let token_a = "eict_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
        let token_b = "eict_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
        let ct_a = encrypt(token_a, &hash(token_a), &key).unwrap();
        let ct_b = encrypt(token_b, &hash(token_b), &key).unwrap();
        assert_ne!(ct_a, ct_b);
    }
}
