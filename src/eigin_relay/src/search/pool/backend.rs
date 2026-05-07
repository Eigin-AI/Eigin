use async_trait::async_trait;
use bytes::Bytes;
use std::fmt;

use crate::error::AppError;

#[derive(Debug)]
pub enum BackendError {
    NotFound,
    Serialise(String),
    Request {
        message: String,
        status_code: Option<u16>,
    },
    Conflict(String),
    Other(String),
}

impl fmt::Display for BackendError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            BackendError::NotFound => write!(f, "not found"),
            BackendError::Serialise(msg) => write!(f, "serialisation error: {}", msg),
            BackendError::Request { message, status_code } => {
                if let Some(code) = status_code {
                    write!(f, "request error {}: {}", code, message)
                } else {
                    write!(f, "request error: {}", message)
                }
            }
            BackendError::Conflict(msg) => write!(f, "conflict: {}", msg),
            BackendError::Other(msg) => write!(f, "{}", msg),
        }
    }
}

impl std::error::Error for BackendError {}

impl BackendError {
    pub fn is_transient(&self) -> bool {
        match self {
            BackendError::Conflict(_) => true,
            BackendError::Request { status_code, .. } => {
                if let Some(code) = status_code {
                    (500..=599).contains(code) || *code == 429
                } else {
                    false
                }
            }
            BackendError::Other(_) => false,
            _ => false,
        }
    }
}

impl From<BackendError> for AppError {
    fn from(e: BackendError) -> Self {
        match e {
            BackendError::Conflict(msg) => AppError::Internal(msg),
            BackendError::NotFound => AppError::Internal("backend not found".into()),
            BackendError::Serialise(msg) => AppError::Internal(format!("serialise failed: {msg}")),
            BackendError::Request { message, .. } => AppError::Internal(message),
            BackendError::Other(msg) => AppError::Internal(msg),
        }
    }
}

pub struct GetResponse {
    pub bytes: Bytes,
    pub meta: Option<String>,
}

#[async_trait]
pub trait PoolBackend: Send + Sync {
    async fn read_state(&self, current_month: &str) -> Result<PoolState, BackendError>;
    async fn write_state(&self, state: &PoolState) -> Result<Option<String>, BackendError>;
}

#[derive(serde::Serialize, serde::Deserialize)]
pub struct PoolState {
    pub month: String,
    pub used: u64,
}
