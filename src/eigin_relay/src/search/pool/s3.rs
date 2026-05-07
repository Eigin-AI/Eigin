use async_trait::async_trait;
use bytes::Bytes;
use minio::s3::MinioClient;
use minio::s3::creds::StaticProvider;
use minio::s3::error::{Error as MinioError, S3ServerError};
use minio::s3::http::BaseUrl;
use minio::s3::multimap_ext::Multimap;
use minio::s3::response_traits::HasEtagFromHeaders;
use minio::s3::types::S3Api;
use std::sync::Mutex;

use super::backend::{BackendError, PoolBackend, PoolState};

const MAX_SAVE_RETRIES: usize = 3;

// ---------------------------------------------------------------------------
// S3Client trait — the abstraction we actually care about.
// MinioS3Client is the production implementation; MockS3Client is for tests.
// ---------------------------------------------------------------------------

#[async_trait]
pub trait S3Client: Send + Sync {
    async fn get(&self) -> Result<(Bytes, Option<String>), BackendError>;
    async fn put(
        &self,
        body: Bytes,
        if_match: Option<&str>,
    ) -> Result<Option<String>, BackendError>;
}

// ---------------------------------------------------------------------------
// Production implementation
// ---------------------------------------------------------------------------

pub struct MinioS3Client {
    client: MinioClient,
    bucket: String,
    key: String,
}

impl MinioS3Client {
    pub fn new(
        endpoint: &str,
        access_key: &str,
        secret_key: &str,
        bucket: String,
        key: String,
    ) -> Result<Self, BackendError> {
        let base_url: BaseUrl = endpoint
            .parse()
            .map_err(|e| BackendError::Other(format!("invalid S3 endpoint: {e}")))?;
        let credentials = StaticProvider::new(access_key, secret_key, None);
        let client = MinioClient::new(base_url, Some(credentials), None, None)
            .map_err(|e| BackendError::Other(format!("failed to create S3 client: {e}")))?;
        Ok(Self {
            client,
            bucket,
            key,
        })
    }
}

#[async_trait]
impl S3Client for MinioS3Client {
    async fn get(&self) -> Result<(Bytes, Option<String>), BackendError> {
        let resp = self
            .client
            .get_object(&self.bucket, &self.key)
            .map_err(|e| BackendError::Other(format!("S3 validation error: {e}")))?
            .build()
            .send()
            .await
            .map_err(map_minio_error)?;

        let etag = resp.etag().ok().map(|e| e.to_string());
        let bytes = resp.into_bytes().await.map_err(|e| BackendError::Request {
            message: format!("S3 get body read failed: {e}"),
            status_code: None,
        })?;

        Ok((bytes, etag))
    }

    async fn put(
        &self,
        body: Bytes,
        if_match: Option<&str>,
    ) -> Result<Option<String>, BackendError> {
        let extra: Multimap = if_match
            .map(|etag| {
                let mut m = Multimap::new();
                m.insert("if-match".to_string(), etag.to_string());
                m
            })
            .unwrap_or_default();

        let resp = self
            .client
            .put_object_content(&self.bucket, &self.key, body)
            .map_err(|e| BackendError::Other(format!("S3 validation error: {e}")))?
            .extra_headers(Some(extra))
            .build()
            .send()
            .await
            .map_err(map_minio_error)?;

        Ok(resp.etag().ok().map(|e| e.to_string()))
    }
}

fn map_minio_error(e: MinioError) -> BackendError {
    match e {
        MinioError::S3Server(S3ServerError::HttpError(412, _)) => {
            BackendError::Conflict("ETag conflict".into())
        }
        MinioError::S3Server(S3ServerError::HttpError(status, body)) => BackendError::Request {
            message: format!("S3 request failed: {status} — {body}"),
            status_code: Some(status),
        },
        e => BackendError::Other(format!("S3 error: {e}")),
    }
}

// ---------------------------------------------------------------------------
// S3Backend — owns the client and the ETag cache
// ---------------------------------------------------------------------------

pub struct S3Backend {
    client: Box<dyn S3Client>,
    etag: Mutex<Option<String>>,
}

impl S3Backend {
    pub fn new(
        bucket: String,
        key: String,
        endpoint: String,
        access_key_id: String,
        secret_access_key: String,
    ) -> Self {
        let client = MinioS3Client::new(&endpoint, &access_key_id, &secret_access_key, bucket, key)
            .expect("failed to initialise S3 client");
        Self::with_client(Box::new(client))
    }

    pub fn with_client(client: Box<dyn S3Client>) -> Self {
        Self {
            client,
            etag: Mutex::new(None),
        }
    }

    pub async fn initial_fetch(&self) -> Result<(Bytes, Option<String>), BackendError> {
        self.client.get().await
    }
}

#[async_trait]
impl PoolBackend for S3Backend {
    async fn read_state(&self, current_month: &str) -> Result<PoolState, BackendError> {
        let (bytes, _etag) = self.client.get().await?;
        let state = serde_json::from_slice::<PoolState>(&bytes)
            .map_err(|e| BackendError::Serialise(e.to_string()))?;
        if state.month != current_month {
            return Ok(PoolState {
                month: current_month.to_string(),
                used: 0,
            });
        }
        Ok(state)
    }

    async fn write_state(&self, state: &PoolState) -> Result<Option<String>, BackendError> {
        let current_etag = self.etag.lock().unwrap().clone();
        let json =
            serde_json::to_string(state).map_err(|e| BackendError::Serialise(e.to_string()))?;
        let mut body = Bytes::from(json.into_bytes());

        for attempt in 0..=MAX_SAVE_RETRIES {
            match self.client.put(body.clone(), current_etag.as_deref()).await {
                Ok(new_etag) => {
                    if let Some(ref et) = new_etag {
                        *self.etag.lock().unwrap() = Some(et.clone());
                    }
                    return Ok(new_etag);
                }
                Err(BackendError::Conflict(msg)) => {
                    if attempt == MAX_SAVE_RETRIES {
                        return Err(BackendError::Conflict(format!(
                            "S3 pool persist failed after {MAX_SAVE_RETRIES} ETag conflicts: {msg}"
                        )));
                    }
                    tracing::warn!(attempt, "S3 ETag conflict, re-reading and retrying");
                    let (remote_bytes, _) = self.client.get().await?;
                    let remote: PoolState = serde_json::from_slice(&remote_bytes)
                        .map_err(|e| BackendError::Serialise(e.to_string()))?;
                    let merged = PoolState {
                        month: remote.month,
                        used: remote.used.max(state.used),
                    };
                    body = Bytes::from(
                        serde_json::to_string(&merged)
                            .map_err(|e| BackendError::Serialise(e.to_string()))?
                            .into_bytes(),
                    );
                }
                Err(e) if e.is_transient() => {
                    if attempt == MAX_SAVE_RETRIES {
                        return Err(e);
                    }
                    tracing::warn!(attempt, error = %e, "S3 transient error, retrying");
                    tokio::time::sleep(tokio::time::Duration::from_millis(
                        100 * 2u64.pow(attempt as u32),
                    ))
                    .await;
                }
                Err(e) => return Err(e),
            }
        }
        Ok(current_etag)
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    struct MockS3Client {
        responses: Mutex<Vec<Result<(Bytes, Option<String>), BackendError>>>,
    }

    impl MockS3Client {
        fn new(responses: Vec<Result<(Bytes, Option<String>), BackendError>>) -> Self {
            Self {
                responses: Mutex::new(responses),
            }
        }
    }

    #[async_trait]
    impl S3Client for MockS3Client {
        async fn get(&self) -> Result<(Bytes, Option<String>), BackendError> {
            self.responses.lock().unwrap().remove(0)
        }

        async fn put(
            &self,
            _body: Bytes,
            _if_match: Option<&str>,
        ) -> Result<Option<String>, BackendError> {
            self.responses
                .lock()
                .unwrap()
                .remove(0)
                .map(|(_, etag)| etag)
        }
    }

    fn ok(body: &str, etag: &str) -> Result<(Bytes, Option<String>), BackendError> {
        Ok((Bytes::from(body.to_string()), Some(etag.to_string())))
    }

    fn ok_no_etag(body: &str) -> Result<(Bytes, Option<String>), BackendError> {
        Ok((Bytes::from(body.to_string()), None))
    }

    fn conflict() -> Result<(Bytes, Option<String>), BackendError> {
        Err(BackendError::Conflict("ETag conflict".into()))
    }

    fn transient() -> Result<(Bytes, Option<String>), BackendError> {
        Err(BackendError::Request {
            message: "service unavailable".into(),
            status_code: Some(503),
        })
    }

    fn forbidden() -> Result<(Bytes, Option<String>), BackendError> {
        Err(BackendError::Request {
            message: "forbidden".into(),
            status_code: Some(403),
        })
    }

    fn make_backend(responses: Vec<Result<(Bytes, Option<String>), BackendError>>) -> S3Backend {
        S3Backend::with_client(Box::new(MockS3Client::new(responses)))
    }

    #[tokio::test]
    async fn s3_read_state_new_month_resets() {
        let backend = make_backend(vec![ok_no_etag(r#"{"month":"2026-04","used":100}"#)]);
        let state = backend.read_state("2026-05").await.unwrap();
        assert_eq!(state.month, "2026-05");
        assert_eq!(state.used, 0);
    }

    #[tokio::test]
    async fn s3_write_state_etag_conflict_retries() {
        let backend = make_backend(vec![
            conflict(),
            ok(r#"{"month":"2026-05","used":10}"#, "\"remote\""),
            ok("", "\"merged\""),
        ]);
        let state = PoolState {
            month: "2026-05".to_string(),
            used: 6,
        };
        let result = backend.write_state(&state).await.unwrap();
        assert_eq!(result, Some("\"merged\"".to_string()));
    }

    #[tokio::test]
    async fn s3_write_state_transient_error_retries() {
        let backend = make_backend(vec![transient(), ok("", "\"success\"")]);
        let state = PoolState {
            month: "2026-05".to_string(),
            used: 1,
        };
        let result = backend.write_state(&state).await.unwrap();
        assert_eq!(result, Some("\"success\"".to_string()));
    }

    #[tokio::test]
    async fn s3_write_state_non_transient_error_fails() {
        let backend = make_backend(vec![forbidden()]);
        let state = PoolState {
            month: "2026-05".to_string(),
            used: 1,
        };
        let err = backend.write_state(&state).await.unwrap_err();
        assert!(matches!(err, BackendError::Request { .. }));
    }
}
