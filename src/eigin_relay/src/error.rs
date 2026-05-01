//! Error types for the relay service.

use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde_json::json;

/// Application-level errors returned as HTTP responses.
///
/// Each variant maps to a specific HTTP status code and includes
/// a user-facing error message.
#[derive(Debug)]
pub enum AppError {
    /// Missing or invalid authentication key (401).
    Unauthorized,
    /// Malformed request or missing parameters (400).
    BadRequest(String),
    /// Rate limit exceeded for client IP (429).
    RateLimited,
    /// Monthly search quota exhausted (429).
    PoolExhausted,
    /// Upstream search service error (502).
    Upstream(String),
    /// Internal server error (500).
    Internal(String),
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, message) = match self {
            Self::Unauthorized => (
                StatusCode::UNAUTHORIZED,
                "invalid or missing API key".into(),
            ),
            Self::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg),
            Self::RateLimited => (
                StatusCode::TOO_MANY_REQUESTS,
                "rate limited — try again shortly".into(),
            ),
            Self::PoolExhausted => (
                StatusCode::TOO_MANY_REQUESTS,
                "monthly search quota exhausted".into(),
            ),
            Self::Upstream(msg) => (StatusCode::BAD_GATEWAY, format!("upstream error: {msg}")),
            Self::Internal(msg) => (StatusCode::INTERNAL_SERVER_ERROR, msg),
        };

        let body = axum::Json(json!({ "error": message }));
        (status, body).into_response()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::to_bytes;
    use axum::http::StatusCode;
    use serde_json::Value;

    async fn extract_json(response: Response) -> Value {
        let body = response.into_body();
        let bytes = to_bytes(body, 1024).await.unwrap();
        serde_json::from_slice(&bytes).unwrap()
    }

    #[tokio::test]
    async fn unauthorized_returns_401() {
        let response = AppError::Unauthorized.into_response();
        assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
        let json = extract_json(response).await;
        assert_eq!(json["error"], "invalid or missing API key");
    }

    #[tokio::test]
    async fn bad_request_returns_400() {
        let response = AppError::BadRequest("test error".into()).into_response();
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
        let json = extract_json(response).await;
        assert_eq!(json["error"], "test error");
    }

    #[tokio::test]
    async fn rate_limited_returns_429() {
        let response = AppError::RateLimited.into_response();
        assert_eq!(response.status(), StatusCode::TOO_MANY_REQUESTS);
        let json = extract_json(response).await;
        assert_eq!(json["error"], "rate limited — try again shortly");
    }

    #[tokio::test]
    async fn pool_exhausted_returns_429() {
        let response = AppError::PoolExhausted.into_response();
        assert_eq!(response.status(), StatusCode::TOO_MANY_REQUESTS);
        let json = extract_json(response).await;
        assert_eq!(json["error"], "monthly search quota exhausted");
    }

    #[tokio::test]
    async fn upstream_returns_502() {
        let response = AppError::Upstream("connection refused".into()).into_response();
        assert_eq!(response.status(), StatusCode::BAD_GATEWAY);
        let json = extract_json(response).await;
        assert_eq!(json["error"], "upstream error: connection refused");
    }

    #[tokio::test]
    async fn internal_returns_500() {
        let response = AppError::Internal("something went wrong".into()).into_response();
        assert_eq!(response.status(), StatusCode::INTERNAL_SERVER_ERROR);
        let json = extract_json(response).await;
        assert_eq!(json["error"], "something went wrong");
    }
}
