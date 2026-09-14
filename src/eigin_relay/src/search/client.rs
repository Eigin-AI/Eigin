//! Abstraction for the upstream search API client.
//!
//! Provides a trait-based interface for making search requests, allowing
//! different implementations (real HTTP client, mock for tests). The
//! production client talks to Staan: https://docs.staan.ai.

use std::time::Duration;

use async_trait::async_trait;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::json;

use super::focus::{MAX_INCLUDE_DOMAINS, SearchFocus};
use crate::AppError;

/// Total request timeout for the search client. Enriched searches (snippet
/// fetch + rerank) run 8-10s upstream, so one deadline over the whole call
/// (connect included) covers the slow path.
const SEARCH_TIMEOUT: Duration = Duration::from_secs(15);

/// Wait before the single retry on an upstream rate-limit response.
const RATE_LIMIT_RETRY_DELAY: Duration = Duration::from_millis(500);

/// Staan hard-rejects queries longer than 400 characters. Truncate rather
/// than fail: a too-long query is a degraded search, not an error.
const MAX_QUERY_CHARS: usize = 400;

/// Builds the production HTTP client for search, with a total request timeout.
pub fn http_client() -> Client {
    Client::builder()
        .timeout(SEARCH_TIMEOUT)
        .build()
        .expect("search HTTP client build failed")
}

/// One reshaped search result, provider-agnostic.
#[derive(Debug, Clone, Serialize)]
pub struct SearchResultItem {
    pub title: String,
    pub url: String,
    /// Short preview from the search provider's index.
    pub desc: String,
    /// Content chunks from the result page, in descending relevance order.
    /// Empty when no chunk cleared the relevance floor.
    pub snippets: Vec<String>,
}

/// Result type returned by search operations.
pub type SearchResult = Vec<SearchResultItem>;

/// Tuning applied to an upstream search, beyond the bare query string.
///
/// `region` is retained for the upcoming locale-based market mapping, until
/// which the production client ignores it.
#[derive(Debug, Clone, Default)]
pub struct SearchOptions {
    /// ISO 3166-1 alpha-2 region code. Accepted but not forwarded upstream.
    pub region: Option<String>,
    /// A named site focus, mapped server-side to a curated domain list.
    pub focus: Option<SearchFocus>,
}

impl SearchOptions {
    /// Parses options from client-supplied query string values.
    ///
    /// A region is only accepted when it looks like a two-letter code — anything
    /// else is dropped here rather than surfaced to the client as an error.
    pub fn parse(region: Option<&str>, focus: Option<&str>) -> Self {
        let region = region
            .map(str::trim)
            .filter(|r| r.len() == 2 && r.chars().all(|c| c.is_ascii_alphabetic()))
            .map(str::to_ascii_uppercase);

        Self {
            region,
            focus: SearchFocus::parse(focus),
        }
    }
}

/// Trait for making search requests to an upstream API.
///
/// Implement this trait to provide custom search backends or mocks. Implementations
/// own the provider's response envelope: callers receive reshaped, provider-agnostic
/// results.
#[async_trait]
pub trait SearchClient: Send + Sync {
    /// Performs a search query.
    ///
    /// - `api_key`: API key for the upstream service.
    /// - `query`: The search query string.
    /// - `options`: Focus tuning applied on top of the bare query.
    async fn search(
        &self,
        api_key: &str,
        query: &str,
        options: &SearchOptions,
    ) -> Result<SearchResult, AppError>;
}

/// Production implementation, backed by the Staan search API (Web Search for
/// AI tier: ranked results plus reranked content snippets).
pub struct StaanSearchClient {
    client: Client,
    base_url: String,
}

impl StaanSearchClient {
    /// Creates a new Staan-backed search client.
    pub fn new(client: Client, base_url: String) -> Self {
        Self { client, base_url }
    }

    /// Sends one search request to Staan and returns the parsed response.
    ///
    /// Retries once, after a short delay, when the upstream rate limit (20 req/s)
    /// rejects the request with a 429.
    async fn post_search(
        &self,
        api_key: &str,
        body: &serde_json::Value,
    ) -> Result<StaanResponse, AppError> {
        let url = format!("{}/search/web", self.base_url.trim_end_matches('/'));

        let mut response = None;
        for attempt in 0..2 {
            let sent = self
                .client
                .post(&url)
                .bearer_auth(api_key)
                .json(body)
                .send()
                .await
                .map_err(|e| AppError::Upstream(e.to_string()))?;

            if sent.status() == reqwest::StatusCode::TOO_MANY_REQUESTS && attempt == 0 {
                tokio::time::sleep(RATE_LIMIT_RETRY_DELAY).await;
                continue;
            }

            response = Some(sent);
            break;
        }

        let response =
            response.ok_or_else(|| AppError::Upstream("search API gave no response".into()))?;

        if !response.status().is_success() {
            return Err(AppError::Upstream(format!(
                "search API returned {}",
                response.status()
            )));
        }

        response
            .json::<StaanResponse>()
            .await
            .map_err(|e| AppError::Upstream(format!("invalid search response: {e}")))
    }
}

/// The subset of Staan's JSON response shape needed to reshape results.
#[derive(Deserialize)]
struct StaanResponse {
    web: StaanWeb,
}

#[derive(Deserialize)]
struct StaanWeb {
    #[serde(default)]
    results: Vec<StaanResult>,
}

#[derive(Deserialize)]
struct StaanResult {
    title: String,
    url: String,
    snippet: String,
    #[serde(default)]
    extra_snippets: Vec<StaanSnippet>,
}

/// A content chunk from a result page.
///
/// The wire format also carries a relevance score per chunk; we deliberately
/// ignore it — serde drops unknown fields and the array arrives sorted by
/// descending score, so order alone is all we forward.
#[derive(Deserialize)]
struct StaanSnippet {
    chunk: String,
}

#[async_trait]
impl SearchClient for StaanSearchClient {
    async fn search(
        &self,
        api_key: &str,
        query: &str,
        options: &SearchOptions,
    ) -> Result<SearchResult, AppError> {
        // Market and snippet tuning are fixed here rather than client-controlled,
        // so no caller can inflate the cost of a search against the shared
        // community quota. Result count is fixed server-side by Staan (10).
        let mut body = json!({
            "q": truncate_query(query),
            "market": "en-gb",
            "extra_snippets": true,
            "max_snippets": 2,
            "min_score": 0.2,
        });

        if let Some(focus) = options.focus {
            // Staan hard-rejects >10 include_domains (HTTP 400, despite docs
            // saying "dropped"). Lists are pruned to <=10, but truncate
            // defensively so a future list edit can't take the relay down.
            let domains: Vec<&str> = focus
                .domains()
                .iter()
                .take(MAX_INCLUDE_DOMAINS)
                .copied()
                .collect();
            body["include_domains"] = json!(domains);
        }

        let parsed = self.post_search(api_key, &body).await?;

        Ok(parsed
            .web
            .results
            .into_iter()
            .map(|r| SearchResultItem {
                title: r.title,
                url: r.url,
                desc: r.snippet,
                snippets: r.extra_snippets.into_iter().map(|s| s.chunk).collect(),
            })
            .collect())
    }
}

/// Truncates the query to Staan's documented maximum on a char boundary.
fn truncate_query(query: &str) -> &str {
    match query.char_indices().nth(MAX_QUERY_CHARS) {
        Some((idx, _)) => &query[..idx],
        None => query,
    }
}

/// Creates a new production search client.
pub fn create_client(client: Client, base_url: &str) -> std::sync::Arc<dyn SearchClient> {
    std::sync::Arc::new(StaanSearchClient::new(client, base_url.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn truncates_long_queries_on_char_boundary() {
        assert_eq!(truncate_query("short"), "short");

        let long = "a".repeat(MAX_QUERY_CHARS + 50);
        assert_eq!(truncate_query(&long).len(), MAX_QUERY_CHARS);

        // Multi-byte query must truncate on a char boundary, not mid-char.
        let multibyte = "Ærø øl økse".repeat(60);
        let truncated = truncate_query(&multibyte);
        assert_eq!(truncated.chars().count(), MAX_QUERY_CHARS);
    }

    #[test]
    fn parses_staan_envelope() {
        let body = r#"{
            "search_id": "abc",
            "query": { "q": "test", "market": "en-gb", "count": 10, "offset": 0 },
            "web": { "results": [
                {
                    "title": "T",
                    "url": "https://example.com",
                    "snippet": "preview",
                    "extra_snippets": [
                        { "chunk": "best", "score": 0.9 },
                        { "chunk": "second", "score": 0.4 }
                    ]
                }
            ]}
        }"#;
        let parsed: StaanResponse = serde_json::from_str(body).expect("parse");
        let item = &parsed.web.results[0];
        assert_eq!(item.title, "T");
        assert_eq!(item.extra_snippets.len(), 2);
        assert_eq!(item.extra_snippets[0].chunk, "best");
    }

    #[test]
    fn parses_envelope_without_snippets() {
        let body = r#"{
            "web": { "results": [
                { "title": "T", "url": "https://example.com", "snippet": "preview" }
            ]}
        }"#;
        let parsed: StaanResponse = serde_json::from_str(body).expect("parse");
        assert!(parsed.web.results[0].extra_snippets.is_empty());
    }

    #[test]
    fn accepts_valid_region_code() {
        let options = SearchOptions::parse(Some("dk"), None);
        assert_eq!(options.region.as_deref(), Some("DK"));
    }

    #[test]
    fn drops_malformed_region_code() {
        assert_eq!(SearchOptions::parse(Some("denmark"), None).region, None);
        assert_eq!(SearchOptions::parse(Some(""), None).region, None);
        assert_eq!(SearchOptions::parse(Some("d1"), None).region, None);
    }
}
