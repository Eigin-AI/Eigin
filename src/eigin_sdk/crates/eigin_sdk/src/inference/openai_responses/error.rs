use super::super::InferenceError;
use serde_json::{Value, json};

pub(super) fn normalize(status: u16, body: Option<String>) -> InferenceError {
    let text = body.as_deref().unwrap_or("");
    for (code, error) in [
        (
            "user_not_eligible",
            InferenceError::SubscriptionPlanNotEligible,
        ),
        (
            "usage_limit_exceeded",
            InferenceError::SubscriptionUsageLimitExceeded,
        ),
        ("invalid_user", InferenceError::SubscriptionInvalidUser),
        (
            "usage_unavailable",
            InferenceError::SubscriptionUsageUnavailable,
        ),
        (
            "user_unavailable",
            InferenceError::SubscriptionUsageUnavailable,
        ),
    ] {
        if text.contains(&format!("subscription_sharing_{code}")) {
            return error;
        }
    }
    if text.contains("subscription_sharing_unsupported_capability") {
        let param = serde_json::from_str::<Value>(text)
            .ok()
            .and_then(|v| v["param"].as_str().map(str::to_owned));
        return InferenceError::SubscriptionUnsupportedCapability { param };
    }
    InferenceError::Http { status, body }
}

pub(super) fn event_error(event: &super::event::Event) -> InferenceError {
    let body = if let Some(error) = event
        .response
        .as_ref()
        .and_then(|response| response.error.as_ref())
    {
        match (error.code.as_deref(), error.param.as_deref()) {
            (Some(code), Some(param)) => Some(json!({"code":code,"param":param}).to_string()),
            (Some(code), None) => Some(code.into()),
            (None, Some(param)) => Some(param.into()),
            _ => error.message.clone(),
        }
    } else if let Some(code) = event.code.as_deref() {
        // Bare-event messages supply the capability detail.
        Some(json!({"code":code,"param":event.message.as_deref().unwrap_or("")}).to_string())
    } else {
        return InferenceError::Http {
            status: 0,
            body: event.message.clone(),
        };
    };
    normalize(0, body)
}
