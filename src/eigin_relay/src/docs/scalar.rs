//! GET /docs/scalar.js — serves the vendored Scalar bundle same-origin.
//!
//! Vendored rather than CDN-loaded: `/docs`'s CSP doesn't need a
//! third-party script origin, and the bundle can't change without a
//! deploy. MIT-licensed; see `LICENSES/vendored-assets.md`.

use axum::http::{HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};

/// The Scalar API reference bundle (v1.65.1), embedded at compile time.
static SCALAR_JS: &str = include_str!("../../assets/scalar-api-reference.js");

/// Serves the vendored Scalar bundle.
pub async fn handler() -> Response {
    let mut response = (StatusCode::OK, SCALAR_JS).into_response();
    response.headers_mut().insert(
        "content-type",
        HeaderValue::from_static("application/javascript; charset=utf-8"),
    );
    response
}
