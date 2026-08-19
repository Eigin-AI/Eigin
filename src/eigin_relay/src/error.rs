//! Error types for the relay service.

use axum::extract::Request;
use axum::http::StatusCode;
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};
use serde_json::json;

/// Log severity for an error response, chosen per variant.
#[derive(Clone, Copy)]
enum Severity {
    Error,
    Warn,
    Debug,
}

/// Diagnostic detail for an error response, attached as a response extension.
///
/// Read at the return boundary by [`log_errors`] and never serialized into the
/// client-facing body. For server faults `detail` is internal detail we keep out
/// of the response (CASA 6.2.1); it is safe by construction (never an upstream
/// body, which could echo the prompt).
#[derive(Clone)]
struct ErrorLog {
    severity: Severity,
    error_type: &'static str,
    detail: String,
}

/// Logs the error detail of any response carrying an [`ErrorLog`] extension.
///
/// Runs at the return boundary so every `AppError` is logged exactly once, where
/// the response is actually handed back — server faults visibly, client errors at
/// debug. The detail lives in a response extension, never the body.
pub async fn log_errors(request: Request, next: Next) -> Response {
    let response = next.run(request).await;
    if let Some(log) = response.extensions().get::<ErrorLog>() {
        let status = response.status();
        match log.severity {
            Severity::Error => {
                tracing::error!(%status, error_type = log.error_type, detail = %log.detail, "request error")
            }
            Severity::Warn => {
                tracing::warn!(%status, error_type = log.error_type, detail = %log.detail, "request error")
            }
            Severity::Debug => {
                tracing::debug!(%status, error_type = log.error_type, detail = %log.detail, "request error")
            }
        }
    }
    response
}

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
        // Each variant yields its status, the client-facing message, and an ErrorLog.
        // For client errors (4xx) the message and log detail are the same client input
        // (logged at debug). For server faults (5xx) the client sees a fixed message
        // while the internal detail is kept for logs only (CASA 6.2.1).
        let (status, message, log) = match self {
            Self::Unauthorized => (
                StatusCode::UNAUTHORIZED,
                "invalid or missing API key".to_string(),
                ErrorLog {
                    severity: Severity::Debug,
                    error_type: "authentication_error",
                    detail: "unauthorized".into(),
                },
            ),
            Self::BadRequest(msg) => (
                StatusCode::BAD_REQUEST,
                msg.clone(),
                ErrorLog {
                    severity: Severity::Debug,
                    error_type: "invalid_request_error",
                    detail: msg,
                },
            ),
            Self::UnprocessableEntity(msg) => (
                StatusCode::UNPROCESSABLE_ENTITY,
                msg.clone(),
                ErrorLog {
                    severity: Severity::Debug,
                    error_type: "invalid_request_error",
                    detail: msg,
                },
            ),
            Self::InsufficientCredits => (
                StatusCode::PAYMENT_REQUIRED,
                "insufficient credits".to_string(),
                ErrorLog {
                    severity: Severity::Debug,
                    error_type: "insufficient_credits",
                    detail: "insufficient credits".into(),
                },
            ),
            Self::RateLimited => (
                StatusCode::TOO_MANY_REQUESTS,
                "rate limited — try again shortly".to_string(),
                ErrorLog {
                    severity: Severity::Debug,
                    error_type: "rate_limit_error",
                    detail: "rate limited".into(),
                },
            ),
            Self::PoolExhausted => (
                StatusCode::TOO_MANY_REQUESTS,
                "monthly search quota exhausted".to_string(),
                ErrorLog {
                    severity: Severity::Debug,
                    error_type: "rate_limit_error",
                    detail: "pool exhausted".into(),
                },
            ),
            Self::SandboxBudgetExhausted => (
                StatusCode::TOO_MANY_REQUESTS,
                "sandbox credit budget exhausted — try again later".to_string(),
                ErrorLog {
                    severity: Severity::Debug,
                    error_type: "sandbox_budget_exhausted",
                    detail: "sandbox budget exhausted".into(),
                },
            ),
            Self::ServiceUnavailable(detail) => (
                StatusCode::SERVICE_UNAVAILABLE,
                "service temporarily unavailable".to_string(),
                ErrorLog {
                    severity: Severity::Error,
                    error_type: "service_unavailable",
                    detail,
                },
            ),
            Self::Upstream(detail) => (
                StatusCode::BAD_GATEWAY,
                "upstream service error".to_string(),
                ErrorLog {
                    severity: Severity::Warn,
                    error_type: "upstream_error",
                    detail,
                },
            ),
            Self::Internal(detail) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                "internal server error".to_string(),
                ErrorLog {
                    severity: Severity::Error,
                    error_type: "internal_error",
                    detail,
                },
            ),
        };

        // Use OpenAI-compatible error format so existing inference clients handle errors correctly.
        let body = axum::Json(json!({
            "error": {
                "message": message,
                "type": log.error_type,
            }
        }));
        // The detail rides along as an extension, logged at the return boundary
        // by `log_errors`, never in the client-facing body.
        let mut response = (status, body).into_response();
        response.extensions_mut().insert(log);
        response
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

    /// The internal detail carried for logging, from the response extension.
    fn log_detail(response: &Response) -> String {
        response
            .extensions()
            .get::<ErrorLog>()
            .expect("ErrorLog extension")
            .detail
            .clone()
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
    async fn upstream_returns_opaque_502() {
        let response = AppError::Upstream("provider berget returned 500".into()).into_response();
        assert_eq!(response.status(), StatusCode::BAD_GATEWAY);
        // Detail is kept for logging in the extension, not the body.
        assert_eq!(log_detail(&response), "provider berget returned 500");
        let json = extract_json(response).await;
        assert_eq!(json["error"]["message"], "upstream service error");
        assert_eq!(json["error"]["type"], "upstream_error");
        // The carried detail must never reach the client body.
        assert!(
            !json["error"]["message"]
                .as_str()
                .unwrap()
                .contains("provider")
        );
    }

    #[tokio::test]
    async fn internal_returns_opaque_500() {
        let response =
            AppError::Internal("database error: connection refused".into()).into_response();
        assert_eq!(response.status(), StatusCode::INTERNAL_SERVER_ERROR);
        assert_eq!(log_detail(&response), "database error: connection refused");
        let json = extract_json(response).await;
        assert_eq!(json["error"]["message"], "internal server error");
        assert_eq!(json["error"]["type"], "internal_error");
        assert!(
            !json["error"]["message"]
                .as_str()
                .unwrap()
                .contains("database")
        );
    }

    #[tokio::test]
    async fn service_unavailable_returns_opaque_503() {
        let response =
            AppError::ServiceUnavailable("provider berget not configured".into()).into_response();
        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
        assert_eq!(log_detail(&response), "provider berget not configured");
        let json = extract_json(response).await;
        assert_eq!(json["error"]["message"], "service temporarily unavailable");
        assert_eq!(json["error"]["type"], "service_unavailable");
        assert!(
            !json["error"]["message"]
                .as_str()
                .unwrap()
                .contains("provider")
        );
    }
}
