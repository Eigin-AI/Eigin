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
    /// Request validation failed — well-formed but semantically invalid (422).
    UnprocessableEntity(String),
    /// Insufficient credits to process the request (402).
    InsufficientCredits,
    /// Rate limit exceeded for client IP or token (429).
    RateLimited,
    /// Monthly search quota exhausted (429).
    PoolExhausted,
    /// Sandbox credit-issuance budget exhausted for the current period (429).
    SandboxBudgetExhausted,
    /// Upstream service unavailable or not configured (503).
    ServiceUnavailable(String),
    /// Upstream search service error (502).
    Upstream(String),
    /// Internal server error (500).
    Internal(String),
}

impl std::fmt::Display for AppError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Unauthorized => write!(f, "unauthorized"),
            Self::BadRequest(msg) => write!(f, "bad request: {msg}"),
            Self::UnprocessableEntity(msg) => write!(f, "unprocessable entity: {msg}"),
            Self::InsufficientCredits => write!(f, "insufficient credits"),
            Self::RateLimited => write!(f, "rate limited"),
            Self::PoolExhausted => write!(f, "pool exhausted"),
            Self::SandboxBudgetExhausted => write!(f, "sandbox budget exhausted"),
            Self::ServiceUnavailable(msg) => write!(f, "service unavailable: {msg}"),
            Self::Upstream(msg) => write!(f, "upstream error: {msg}"),
            Self::Internal(msg) => write!(f, "internal error: {msg}"),
        }
    }
}

impl std::error::Error for AppError {}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, message, error_type) = match self {
            Self::Unauthorized => (
                StatusCode::UNAUTHORIZED,
                "invalid or missing API key".into(),
                "authentication_error",
            ),
            Self::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg, "invalid_request_error"),
            Self::UnprocessableEntity(msg) => (
                StatusCode::UNPROCESSABLE_ENTITY,
                msg,
                "invalid_request_error",
            ),
            Self::InsufficientCredits => (
                StatusCode::PAYMENT_REQUIRED,
                "insufficient credits".into(),
                "insufficient_credits",
            ),
            Self::RateLimited => (
                StatusCode::TOO_MANY_REQUESTS,
                "rate limited — try again shortly".into(),
                "rate_limit_error",
            ),
            Self::PoolExhausted => (
                StatusCode::TOO_MANY_REQUESTS,
                "monthly search quota exhausted".into(),
                "rate_limit_error",
            ),
            Self::SandboxBudgetExhausted => (
                StatusCode::TOO_MANY_REQUESTS,
                "sandbox credit budget exhausted — try again later".into(),
                "sandbox_budget_exhausted",
            ),
            Self::ServiceUnavailable(msg) => {
                (StatusCode::SERVICE_UNAVAILABLE, msg, "service_unavailable")
            }
            Self::Upstream(msg) => (
                StatusCode::BAD_GATEWAY,
                format!("upstream error: {msg}"),
                "upstream_error",
            ),
            Self::Internal(msg) => (StatusCode::INTERNAL_SERVER_ERROR, msg, "internal_error"),
        };

        // Use OpenAI-compatible error format so existing inference clients handle errors correctly.
        let body = axum::Json(json!({
            "error": {
                "message": message,
                "type": error_type,
            }
        }));
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
        assert_eq!(json["error"]["message"], "invalid or missing API key");
    }

    #[tokio::test]
    async fn bad_request_returns_400() {
        let response = AppError::BadRequest("test error".into()).into_response();
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
        let json = extract_json(response).await;
        assert_eq!(json["error"]["message"], "test error");
    }

    #[tokio::test]
    async fn insufficient_credits_returns_402() {
        let response = AppError::InsufficientCredits.into_response();
        assert_eq!(response.status(), StatusCode::PAYMENT_REQUIRED);
        let json = extract_json(response).await;
        assert_eq!(json["error"]["type"], "insufficient_credits");
    }

    #[tokio::test]
    async fn rate_limited_returns_429() {
        let response = AppError::RateLimited.into_response();
        assert_eq!(response.status(), StatusCode::TOO_MANY_REQUESTS);
        let json = extract_json(response).await;
        assert_eq!(json["error"]["message"], "rate limited — try again shortly");
    }

    #[tokio::test]
    async fn pool_exhausted_returns_429() {
        let response = AppError::PoolExhausted.into_response();
        assert_eq!(response.status(), StatusCode::TOO_MANY_REQUESTS);
        let json = extract_json(response).await;
        assert_eq!(json["error"]["message"], "monthly search quota exhausted");
    }

    #[tokio::test]
    async fn sandbox_budget_exhausted_returns_429() {
        let response = AppError::SandboxBudgetExhausted.into_response();
        assert_eq!(response.status(), StatusCode::TOO_MANY_REQUESTS);
        let json = extract_json(response).await;
        assert_eq!(json["error"]["type"], "sandbox_budget_exhausted");
    }

    #[tokio::test]
    async fn upstream_returns_502() {
        let response = AppError::Upstream("connection refused".into()).into_response();
        assert_eq!(response.status(), StatusCode::BAD_GATEWAY);
        let json = extract_json(response).await;
        assert_eq!(
            json["error"]["message"],
            "upstream error: connection refused"
        );
    }

    #[tokio::test]
    async fn internal_returns_500() {
        let response = AppError::Internal("something went wrong".into()).into_response();
        assert_eq!(response.status(), StatusCode::INTERNAL_SERVER_ERROR);
        let json = extract_json(response).await;
        assert_eq!(json["error"]["message"], "something went wrong");
    }
}
