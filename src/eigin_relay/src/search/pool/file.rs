use async_trait::async_trait;
use std::path::PathBuf;

use super::backend::{BackendError, PoolBackend, PoolState};

pub struct FileBackend {
    path: PathBuf,
}

impl FileBackend {
    pub fn new(path: PathBuf) -> Self {
        Self { path }
    }
}

#[async_trait]
impl PoolBackend for FileBackend {
    async fn read_state(&self, current_month: &str) -> Result<PoolState, BackendError> {
        let contents = std::fs::read_to_string(&self.path).map_err(|_| BackendError::NotFound)?;
        let state = serde_json::from_str::<PoolState>(&contents)
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
        let tmp = self.path.with_extension("json.tmp");
        let json =
            serde_json::to_string(state).map_err(|e| BackendError::Serialise(e.to_string()))?;
        std::fs::write(&tmp, &json)
            .map_err(|e| BackendError::Other(format!("write failed: {e}")))?;
        std::fs::rename(&tmp, &self.path)
            .map_err(|e| BackendError::Other(format!("rename failed: {e}")))?;
        Ok(None)
    }
}
