//! Abstraction for the upstream search API client.
//!
//! Provides a trait-based interface for making search requests, allowing
//! different implementations (real HTTP client, mock for tests).

use async_trait::async_trait;
use reqwest::Client;

/// Result type returned by search operations.
pub type SearchResult = Vec<u8>;

/// Trait for making search requests to an upstream API.
///
/// Implement this trait to provide custom search backends or mocks.
#[async_trait]
pub trait SearchClient: Send + Sync {
    /// Performs a search query.
    ///
    /// - `api_key`: API key for the upstream service.
    /// - `query`: The search query string.
    ///
    /// Returns the raw response body bytes on success.
    async fn search(&self, api_key: &str, query: &str) -> Result<SearchResult, crate::AppError>;
}

/// Production implementation using reqwest.
pub struct ReqwestClient {
    client: Client,
    base_url: String,
}

impl ReqwestClient {
    /// Creates a new reqwest-based search client.
    pub fn new(client: Client, base_url: String) -> Self {
        Self { client, base_url }
    }
}

#[async_trait]
impl SearchClient for ReqwestClient {
    async fn search(&self, api_key: &str, query: &str) -> Result<SearchResult, crate::AppError> {
        let url = format!(
            "{}/search?api_key={}&q={}&fmt=json",
            self.base_url,
            api_key,
            urlencoding::encode(query)
        );

        let response = self
            .client
            .get(&url)
            .send()
            .await
            .map_err(|e| crate::AppError::Upstream(e.to_string()))?;

        if !response.status().is_success() {
            return Err(crate::AppError::Upstream(format!(
                "search API returned {}",
                response.status()
            )));
        }

        let body = response
            .bytes()
            .await
            .map_err(|e| crate::AppError::Upstream(e.to_string()))?;

        Ok(body.to_vec())
    }
}

/// Creates a new production search client.
pub fn create_client(client: Client, base_url: &str) -> std::sync::Arc<dyn SearchClient> {
    std::sync::Arc::new(ReqwestClient::new(client, base_url.to_string()))
}
