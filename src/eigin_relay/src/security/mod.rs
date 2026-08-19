//! Baseline security response headers (CASA 4.1.1).
//!
//! Applied globally so every endpoint — health, docs, webhooks, search,
//! credits, inference — carries a hardened header set, not just the ones
//! that happen to render HTML.

pub mod csp;

use axum::extract::Request;
use axum::http::HeaderValue;
use axum::middleware::Next;
use axum::response::Response;

use csp::{ContentSecurityPolicy, Source};

/// Strict default CSP for JSON/API responses that don't render markup.
fn default_csp() -> HeaderValue {
    ContentSecurityPolicy::new()
        .default_src(&[Source::None])
        .frame_ancestors(&[Source::None])
        .into_header_value()
}

/// Sets baseline security headers on every response.
///
/// `Content-Security-Policy` is only set if the handler hasn't already set
/// one — this lets `/docs` supply its own relaxed policy for the Scalar
/// bundle it loads from jsDelivr, while every other endpoint gets the
/// strict default.
pub async fn security_headers(request: Request, next: Next) -> Response {
    let mut response = next.run(request).await;
    let headers = response.headers_mut();

    headers.insert(
        "x-content-type-options",
        HeaderValue::from_static("nosniff"),
    );
    headers.insert("referrer-policy", HeaderValue::from_static("no-referrer"));
    headers.insert("x-frame-options", HeaderValue::from_static("DENY"));
    headers.insert(
        "permissions-policy",
        HeaderValue::from_static("geolocation=(), camera=(), microphone=()"),
    );
    // The Scaleway edge redirects plaintext to HTTPS (`http_option = "redirected"`)
    // but doesn't itself instruct clients to stop attempting plaintext, so the app
    // sets HSTS. Harmless on the rare non-HTTPS hop: browsers ignore it there.
    headers.insert(
        "strict-transport-security",
        HeaderValue::from_static("max-age=63072000; includeSubDomains"),
    );
    headers
        .entry("content-security-policy")
        .or_insert_with(default_csp);

    response
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::Router;
    use axum::body::Body;
    use axum::http::{Request as HttpRequest, StatusCode};
    use axum::middleware;
    use axum::routing::get;
    use tower::ServiceExt;

    async fn json_ok() -> &'static str {
        "ok"
    }

    async fn html_with_own_csp() -> Response {
        let mut response = axum::response::Html("<html></html>").into_response();
        response.headers_mut().insert(
            "content-security-policy",
            HeaderValue::from_static("default-src 'self' https://cdn.jsdelivr.net"),
        );
        response
    }

    use axum::response::IntoResponse;

    fn router() -> Router {
        Router::new()
            .route("/json", get(json_ok))
            .route("/docs", get(html_with_own_csp))
            .layer(middleware::from_fn(security_headers))
    }

    #[tokio::test]
    async fn applies_strict_default_csp_and_baseline_headers() {
        let response = router()
            .oneshot(
                HttpRequest::builder()
                    .uri("/json")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(
            response.headers().get("x-content-type-options").unwrap(),
            "nosniff"
        );
        assert_eq!(
            response.headers().get("referrer-policy").unwrap(),
            "no-referrer"
        );
        assert_eq!(response.headers().get("x-frame-options").unwrap(), "DENY");
        assert_eq!(
            response.headers().get("content-security-policy").unwrap(),
            "default-src 'none'; frame-ancestors 'none'"
        );
        assert_eq!(
            response.headers().get("strict-transport-security").unwrap(),
            "max-age=63072000; includeSubDomains"
        );
    }

    #[tokio::test]
    async fn preserves_handler_supplied_csp() {
        let response = router()
            .oneshot(
                HttpRequest::builder()
                    .uri("/docs")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        let csp = response
            .headers()
            .get("content-security-policy")
            .unwrap()
            .to_str()
            .unwrap();
        assert!(csp.contains("cdn.jsdelivr.net"));
        assert_eq!(
            response.headers().get("x-content-type-options").unwrap(),
            "nosniff"
        );
    }
}
