use super::{LocalEventCallback, LocalOpenCallback, LocalToolSession};
use crate::inference::InferenceCompletionInput;
use std::sync::Arc;

/// Host model loading and execution. Methods return immediately and complete asynchronously.
#[uniffi::export(callback_interface)]
pub trait LocalInferenceExecutor: Send + Sync {
    /// Prepares one request; the host owns files, resource checks, and hardware integration.
    fn start_request(
        &self,
        id: u64,
        input: InferenceCompletionInput,
        tools: Option<Arc<LocalToolSession>>,
        completion: Arc<LocalOpenCallback>,
    );
    /// Delivers one event or EOF; only one read is outstanding per request.
    fn read(&self, id: u64, completion: Arc<LocalEventCallback>);
    /// Stops native generation and releases this request. Safe to repeat.
    fn close(&self, id: u64);
}
