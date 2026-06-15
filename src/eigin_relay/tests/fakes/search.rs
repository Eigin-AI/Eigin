use eigin_relay::AppError;
use eigin_relay::SearchClient;

/// No-op search client that always returns an empty result. Used where search
/// is not under test.
pub struct NoopSearch;

#[async_trait::async_trait]
impl SearchClient for NoopSearch {
    async fn search(&self, _query: &str, _api_key: &str) -> Result<Vec<u8>, AppError> {
        Ok(b"{}".to_vec())
    }
}
