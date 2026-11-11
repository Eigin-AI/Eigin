use super::{HttpBodyChunkCallback, HttpResponseHeadCallback};
use std::collections::HashMap;
use std::sync::Arc;

/// Transport failures remain separate from provider HTTP status errors.
#[derive(Clone, Debug, thiserror::Error, uniffi::Error)]
pub enum HttpTransportError {
    #[error("HTTP operation cancelled")]
    Cancelled,
    #[error("HTTP transport: {reason}")]
    Failed {
        reason: String,
        domain: Option<String>,
        code: Option<i64>,
    },
    #[error("HTTP operation already in use")]
    Busy,
}

/// A fully encoded request; adapters must not retry non-idempotent requests.
#[derive(Clone, Debug, uniffi::Record)]
pub struct HttpRequest {
    pub url: String,
    pub method: String,
    pub headers: HashMap<String, String>,
    pub body: Vec<u8>,
}

/// Response metadata delivered before the body is consumed.
#[derive(Clone, Debug, uniffi::Record)]
pub struct HttpResponseHead {
    pub status: u16,
    pub headers: HashMap<String, String>,
}

/// Platform HTTP adapter. Methods return immediately; completions are single-use.
/// Each request ID owns one response and at most one pending read. Close is idempotent.
#[uniffi::export(callback_interface)]
pub trait HttpTransport: Send + Sync {
    /// Starts an exchange and completes its response headers asynchronously.
    fn start_request(
        &self,
        id: u64,
        request: HttpRequest,
        completion: Arc<HttpResponseHeadCallback>,
    );
    /// Returns one bounded chunk, or None at EOF. Preserve bytes and order.
    fn read(&self, id: u64, completion: Arc<HttpBodyChunkCallback>);
    /// Aborts pending I/O and releases all resources for this ID.
    fn close(&self, id: u64);
}
