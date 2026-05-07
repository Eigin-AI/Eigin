use async_trait::async_trait;
use std::path::PathBuf;
use std::sync::Mutex;
use time::OffsetDateTime;
use time::macros::format_description;

use super::backend::{BackendError, PoolBackend, PoolState};
use super::file::FileBackend;
use super::s3::S3Backend;
use crate::error::AppError;

const POOL_OBJECT_KEY: &str = "pool.json";

pub enum PoolConfig {
    InMemory,
    LocalFile(PathBuf),
    S3 {
        bucket: String,
        key: String,
        endpoint: String,
        access_key_id: String,
        secret_access_key: String,
    },
}

impl PoolConfig {
    pub fn from_env() -> Result<Self, String> {
        if let Ok(bucket) = std::env::var("POOL_BUCKET") {
            let key =
                std::env::var("POOL_OBJECT_KEY").unwrap_or_else(|_| POOL_OBJECT_KEY.to_string());
            let endpoint = std::env::var("S3_ENDPOINT")
                .map_err(|_| "S3_ENDPOINT must be set when POOL_BUCKET is set".to_string())?;
            let access_key_id = std::env::var("S3_ACCESS_KEY")
                .map_err(|_| "S3_ACCESS_KEY must be set when POOL_BUCKET is set".to_string())?;
            let secret_access_key = std::env::var("S3_SECRET_KEY")
                .map_err(|_| "S3_SECRET_KEY must be set when POOL_BUCKET is set".to_string())?;
            Ok(Self::S3 {
                bucket,
                key,
                endpoint,
                access_key_id,
                secret_access_key,
            })
        } else if let Ok(file_path) = std::env::var("POOL_FILE_PATH") {
            Ok(Self::LocalFile(PathBuf::from(file_path)))
        } else {
            Ok(Self::InMemory)
        }
    }
}

struct InMemoryBackend;

#[async_trait]
impl PoolBackend for InMemoryBackend {
    async fn read_state(&self, current_month: &str) -> Result<PoolState, BackendError> {
        Ok(PoolState {
            month: current_month.to_string(),
            used: 0,
        })
    }

    async fn write_state(&self, _state: &PoolState) -> Result<Option<String>, BackendError> {
        Ok(None)
    }
}

pub struct Pool {
    state: Mutex<PoolState>,
    max: u64,
    backend: Box<dyn PoolBackend>,
}

impl Pool {
    pub async fn load(max: u64, config: PoolConfig) -> Self {
        let current_month = Self::current_month();
        let backend: Box<dyn PoolBackend> = match config {
            PoolConfig::S3 {
                bucket,
                key,
                endpoint,
                access_key_id,
                secret_access_key,
            } => {
                let s3 = S3Backend::new(
                    bucket.clone(),
                    key.clone(),
                    endpoint.clone(),
                    access_key_id.clone(),
                    secret_access_key.clone(),
                );
                tracing::info!(endpoint = %endpoint, "using S3 pool backend");
                let (initial_bytes, _initial_etag) = match s3.initial_fetch().await {
                    Ok(resp) => (Some(resp.0), resp.1),
                    Err(e) => {
                        tracing::warn!(error = %e, "S3 initial fetch failed, starting with fresh state");
                        (None, None)
                    }
                };
                let state = if let Some(bytes) = &initial_bytes {
                    match serde_json::from_slice::<PoolState>(bytes) {
                        Ok(s) if s.month == current_month => s,
                        _ => PoolState {
                            month: current_month.clone(),
                            used: 0,
                        },
                    }
                } else {
                    PoolState {
                        month: current_month.clone(),
                        used: 0,
                    }
                };
                return Self {
                    state: Mutex::new(state),
                    max,
                    backend: Box::new(s3),
                };
            }
            PoolConfig::LocalFile(path) => {
                tracing::info!(path = %path.display(), "using local file pool backend");
                Box::new(FileBackend::new(path))
            }
            PoolConfig::InMemory => {
                tracing::info!("no persistent backend configured, using in-memory pool");
                return Self {
                    state: Mutex::new(PoolState {
                        month: current_month,
                        used: 0,
                    }),
                    max,
                    backend: Box::new(InMemoryBackend),
                };
            }
        };

        let state = backend
            .read_state(&current_month)
            .await
            .unwrap_or_else(|e| {
                tracing::warn!("pool read failed, starting fresh: {:?}", e);
                PoolState {
                    month: current_month.clone(),
                    used: 0,
                }
            });

        tracing::info!(month = %state.month, used = state.used, max, "pool loaded");

        Self {
            state: Mutex::new(state),
            max,
            backend,
        }
    }

    pub async fn try_consume(&self) -> Result<(), AppError> {
        let state_for_persist = {
            let mut state = self.state.lock().unwrap();
            let current_month = Self::current_month();
            if state.month != current_month {
                tracing::info!(old = %state.month, new = %current_month, "month rolled over, resetting pool");
                state.month = current_month;
                state.used = 0;
            }
            if state.used >= self.max {
                return Err(AppError::PoolExhausted);
            }
            state.used += 1;
            PoolState {
                month: state.month.clone(),
                used: state.used,
            }
        };
        self.backend.write_state(&state_for_persist).await?;
        Ok(())
    }

    pub fn remaining(&self) -> u64 {
        let state = self.state.lock().unwrap();
        self.max.saturating_sub(state.used)
    }

    fn current_month() -> String {
        let now = OffsetDateTime::now_utc();
        let fmt = format_description!("[year]-[month]");
        now.format(&fmt).unwrap()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn within_quota_allows_request() {
        let tmp = tempfile::TempDir::new().unwrap();
        let path = tmp.path().join("pool.json");
        let pool = futures::executor::block_on(Pool::load(10, PoolConfig::LocalFile(path)));
        for _ in 0..10 {
            assert!(futures::executor::block_on(pool.try_consume()).is_ok());
        }
        assert_eq!(pool.remaining(), 0);
    }

    #[test]
    fn over_quota_rejects_request() {
        let tmp = tempfile::TempDir::new().unwrap();
        let path = tmp.path().join("pool.json");
        let pool = futures::executor::block_on(Pool::load(3, PoolConfig::LocalFile(path)));
        for _ in 0..3 {
            futures::executor::block_on(pool.try_consume()).unwrap();
        }
        assert!(matches!(
            futures::executor::block_on(pool.try_consume()),
            Err(AppError::PoolExhausted)
        ));
    }

    #[test]
    fn remaining_counts_down() {
        let tmp = tempfile::TempDir::new().unwrap();
        let path = tmp.path().join("pool.json");
        let pool = futures::executor::block_on(Pool::load(10, PoolConfig::LocalFile(path)));
        assert_eq!(pool.remaining(), 10);
        futures::executor::block_on(pool.try_consume()).unwrap();
        assert_eq!(pool.remaining(), 9);
        futures::executor::block_on(pool.try_consume()).unwrap();
        assert_eq!(pool.remaining(), 8);
    }

    #[test]
    fn load_from_missing_file_starts_at_zero() {
        let tmp = tempfile::TempDir::new().unwrap();
        let nonexistent = tmp.path().join("nonexistent.json");
        let pool = futures::executor::block_on(Pool::load(100, PoolConfig::LocalFile(nonexistent)));
        assert_eq!(pool.remaining(), 100);
    }

    #[test]
    fn load_from_corrupt_file_resets() {
        let tmp = tempfile::TempDir::new().unwrap();
        let path = tmp.path().join("pool.json");
        fs::write(&path, "not valid json {{{").unwrap();
        let pool =
            futures::executor::block_on(Pool::load(100, PoolConfig::LocalFile(path.clone())));
        assert_eq!(pool.remaining(), 100);
    }

    #[test]
    fn load_from_old_month_resets() {
        let tmp = tempfile::TempDir::new().unwrap();
        let path = tmp.path().join("pool.json");
        fs::write(
            &path,
            serde_json::to_string(&PoolState {
                month: "2020-01".to_string(),
                used: 50,
            })
            .unwrap(),
        )
        .unwrap();
        let pool = futures::executor::block_on(Pool::load(100, PoolConfig::LocalFile(path)));
        assert_eq!(pool.remaining(), 100);
    }

    #[test]
    fn persist_writes_to_disk() {
        let tmp = tempfile::TempDir::new().unwrap();
        let path = tmp.path().join("pool.json");
        let pool =
            futures::executor::block_on(Pool::load(100, PoolConfig::LocalFile(path.clone())));
        futures::executor::block_on(pool.try_consume()).unwrap();
        futures::executor::block_on(pool.try_consume()).unwrap();
        let contents = fs::read_to_string(&path).unwrap();
        let state: PoolState = serde_json::from_str(&contents).unwrap();
        assert_eq!(state.used, 2);
    }

    #[test]
    fn in_memory_pool_does_not_persist() {
        let pool = futures::executor::block_on(Pool::load(5, PoolConfig::InMemory));
        futures::executor::block_on(pool.try_consume()).unwrap();
        assert_eq!(pool.remaining(), 4);
    }
}
