//! Grant entitlements: credits issued directly by a trusted (non-store) issuer,
//! proven by an Ed25519-signed JWT.

pub mod verifier;

pub use verifier::{Ed25519GrantVerifier, GrantVerifier, RejectingGrantVerifier, VerifiedGrant};
