//! Client IP resolution behind a trusted proxy.
//!
//! When the app runs behind a proxy, the `ConnectInfo` peer address is the
//! proxy, not the client. The real client is carried in `X-Forwarded-For`.
//! That header is a client-writable list, so its left entries can be forged;
//! only the rightmost entries, appended by proxies we control, are trustworthy.
//! We read the Nth-from-rightmost entry, where N is the number of trusted proxy
//! hops in front of the app.
//!
//! A [`resolve_client_ip`] middleware computes the IP once and stores it as a
//! [`ClientIp`] request extension; handlers and the rate-limit layer read it.

use std::net::{IpAddr, SocketAddr};
use std::sync::Arc;

use axum::extract::{ConnectInfo, FromRequestParts, Request, State};
use axum::http::HeaderMap;
use axum::http::request::Parts;
use axum::middleware::Next;
use axum::response::Response;

use crate::AppState;
use crate::error::AppError;

/// Header carrying the proxy chain's view of the client address.
const FORWARDED_FOR: &str = "x-forwarded-for";

/// The resolved client IP, stored as a request extension by [`resolve_client_ip`].
#[derive(Clone, Copy, Debug)]
pub struct ClientIp(pub IpAddr);

/// Derive the client IP from `X-Forwarded-For`, honoring the trusted-hop count.
///
/// `trusted_hops` is how many proxies we control sit in front of the app —
/// typically 1. Each proxy appends the address it saw, left→right, so counting
/// `trusted_hops` from the right lands on the client address written by our
/// own edge proxy (index `len - trusted_hops`). Anything further left was
/// supplied by the caller and could be forged to dodge rate limiting, so we
/// never trust it.
///
/// Falls back to the `ConnectInfo` peer IP when there is no usable header or
/// `trusted_hops == 0`.
pub fn resolve(headers: &HeaderMap, peer: IpAddr, trusted_hops: usize) -> IpAddr {
    if trusted_hops == 0 {
        return peer;
    }

    let candidate = headers
        .get(FORWARDED_FOR)
        .and_then(|v| v.to_str().ok())
        .and_then(|raw| {
            let ips: Vec<&str> = raw.split(',').map(str::trim).collect();
            // Nth-from-rightmost: skip the client-spoofable left portion.
            ips.len()
                .checked_sub(trusted_hops)
                .and_then(|idx| ips.get(idx))
                .and_then(|s| s.parse::<IpAddr>().ok())
        });

    candidate.unwrap_or(peer)
}

/// Middleware that resolves the client IP once and stores it as a [`ClientIp`]
/// extension for downstream layers and handlers.
pub async fn resolve_client_ip(
    State(state): State<Arc<AppState>>,
    mut request: Request,
    next: Next,
) -> Response {
    let peer = request
        .extensions()
        .get::<ConnectInfo<SocketAddr>>()
        .map(|ci| ci.0.ip())
        .unwrap_or(IpAddr::V4(std::net::Ipv4Addr::UNSPECIFIED));

    let ip = resolve(request.headers(), peer, state.trusted_proxy_hops);
    request.extensions_mut().insert(ClientIp(ip));
    next.run(request).await
}

impl<S> FromRequestParts<S> for ClientIp
where
    S: Send + Sync,
{
    type Rejection = AppError;

    async fn from_request_parts(parts: &mut Parts, _state: &S) -> Result<Self, Self::Rejection> {
        parts
            .extensions
            .get::<ClientIp>()
            .copied()
            .ok_or_else(|| AppError::Internal("client IP not resolved".into()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::Ipv4Addr;

    fn peer() -> IpAddr {
        IpAddr::V4(Ipv4Addr::new(10, 0, 0, 1))
    }

    fn headers(xff: &str) -> HeaderMap {
        let mut h = HeaderMap::new();
        h.insert(FORWARDED_FOR, xff.parse().unwrap());
        h
    }

    #[test]
    fn one_hop_takes_rightmost() {
        let h = headers("1.2.3.4, 5.6.7.8");
        assert_eq!(resolve(&h, peer(), 1), "5.6.7.8".parse::<IpAddr>().unwrap());
    }

    #[test]
    fn spoofed_leftmost_is_ignored() {
        // Client injects a fake leftmost; trusted proxy appends the real client.
        let h = headers("9.9.9.9, 203.0.113.7");
        assert_eq!(
            resolve(&h, peer(), 1),
            "203.0.113.7".parse::<IpAddr>().unwrap()
        );
    }

    #[test]
    fn two_hops_skips_inner_proxy() {
        // [spoof, realclient, edge] with two trusted hops → realclient.
        let h = headers("9.9.9.9, 203.0.113.7, 172.16.0.1");
        assert_eq!(
            resolve(&h, peer(), 2),
            "203.0.113.7".parse::<IpAddr>().unwrap()
        );
    }

    #[test]
    fn missing_header_falls_back_to_peer() {
        let h = HeaderMap::new();
        assert_eq!(resolve(&h, peer(), 1), peer());
    }

    #[test]
    fn zero_hops_uses_peer() {
        let h = headers("1.2.3.4, 5.6.7.8");
        assert_eq!(resolve(&h, peer(), 0), peer());
    }

    #[test]
    fn hops_exceeding_list_falls_back_to_peer() {
        let h = headers("5.6.7.8");
        assert_eq!(resolve(&h, peer(), 2), peer());
    }

    #[test]
    fn unparseable_entry_falls_back_to_peer() {
        let h = headers("not-an-ip");
        assert_eq!(resolve(&h, peer(), 1), peer());
    }

    #[test]
    fn ipv6_entry_parses() {
        let h = headers("2001:db8::1");
        assert_eq!(
            resolve(&h, peer(), 1),
            "2001:db8::1".parse::<IpAddr>().unwrap()
        );
    }
}
