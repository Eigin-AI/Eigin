use super::types::*;
use crate::http::HttpRequest;

pub(crate) fn request(
    config: &InferenceProviderConfig,
    path: &str,
    body: Option<Vec<u8>>,
) -> Result<HttpRequest, InferenceError> {
    let base = config
        .base_url
        .strip_suffix('/')
        .unwrap_or(&config.base_url);
    let url = format!("{base}{path}");
    let parsed = url::Url::parse(&url).map_err(|_| InferenceError::InvalidUrl {
        url: config.base_url.clone(),
    })?;
    if !matches!(parsed.scheme(), "http" | "https") || parsed.host_str().is_none() {
        return Err(InferenceError::InvalidUrl {
            url: config.base_url.clone(),
        });
    }
    let mut headers = std::collections::HashMap::new();
    if !config.api_token.is_empty() {
        headers.insert(
            "authorization".into(),
            format!("Bearer {}", config.api_token),
        );
    }
    if body.is_some() {
        headers.insert("content-type".into(), "application/json".into());
    }
    for (key, value) in &config.extra_headers {
        headers.insert(key.to_ascii_lowercase(), value.clone());
    }
    Ok(HttpRequest {
        url,
        method: if body.is_some() { "POST" } else { "GET" }.into(),
        headers,
        body: body.unwrap_or_default(),
    })
}
