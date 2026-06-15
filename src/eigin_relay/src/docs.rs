//! GET /docs — serves the API reference as an HTML page.
//!
//! The OpenAPI spec (`api.yaml`) is embedded at compile time via `include_str!`.
//! The page uses Scalar loaded from the jsDelivr CDN.

use axum::http::StatusCode;
use axum::response::{Html, IntoResponse, Response};

/// The OpenAPI spec, embedded at compile time.
static SPEC: &str = include_str!("../api.yaml");

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
  <script src="https://cdn.jsdelivr.net/npm/@scalar/api-reference"></script>
</body>
</html>"#,
        spec = SPEC,
    );

    (StatusCode::OK, Html(html)).into_response()
}
