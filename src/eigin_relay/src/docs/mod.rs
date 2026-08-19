//! GET /docs — serves the API reference as an HTML page.
//!
//! The OpenAPI spec (`api.yaml`) is embedded at compile time via `include_str!`.
//! The page uses a vendored Scalar bundle served same-origin (see `scalar`).

pub mod scalar;

use axum::http::StatusCode;
use axum::response::{Html, IntoResponse, Response};

use crate::security::csp::{ContentSecurityPolicy, Source};

/// The OpenAPI spec, embedded at compile time.
static SPEC: &str = include_str!("../../api.yaml");

/// CSP for this page only. The Scalar bundle is vendored and served
/// same-origin, so no third-party origin is needed — only the keywords
/// the bundle itself requires (Vue's runtime template compiler, and the
/// stylesheet it injects at runtime).
fn csp() -> axum::http::HeaderValue {
    // Scalar fetches its bundled fonts from its own font CDN at runtime,
    // separately from the (now vendored) script bundle itself.
    let scalar_fonts = Source::Host("https://fonts.scalar.com");

    ContentSecurityPolicy::new()
        .default_src(&[Source::None])
        .script_src(&[Source::SelfOrigin, Source::UnsafeEval])
        .style_src(&[Source::SelfOrigin, Source::UnsafeInline])
        .font_src(&[Source::SelfOrigin, Source::Data, scalar_fonts])
        .img_src(&[Source::SelfOrigin, Source::Data])
        .connect_src(&[Source::SelfOrigin])
        .frame_ancestors(&[Source::None])
        .into_header_value()
}

/// Serves the API reference page.
///
/// No authentication required — the spec itself contains no secrets.
pub async fn handler() -> Response {
    let html = format!(
        r#"<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Eigin Relay API</title>
  <style>
    body {{ margin: 0; }}
  </style>
</head>
<body>
  <script
    id="api-reference"
    type="application/yaml"
    data-configuration='{{"agent":{{"disabled":true}},"mcp":{{"disabled":true}},"showDeveloperTools":"never","hideTestRequestButton":true}}'
  >{spec}</script>
  <script src="/docs/scalar.js"></script>
</body>
</html>"#,
        spec = SPEC,
    );

    let mut response = (StatusCode::OK, Html(html)).into_response();
    response
        .headers_mut()
        .insert("content-security-policy", csp());
    response
}
