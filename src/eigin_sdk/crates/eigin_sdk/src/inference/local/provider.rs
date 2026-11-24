use super::{LocalInferenceExecutor, LocalInferenceStream, LocalToolSession};
use crate::inference::InferenceCompletionInput;
use std::sync::Arc;

/// A local provider backed by a host execution capability.
#[derive(uniffi::Object)]
pub struct LocalInferenceProvider {
    executor: Arc<dyn LocalInferenceExecutor>,
}
#[uniffi::export]
impl LocalInferenceProvider {
    #[uniffi::constructor]
    pub fn new(executor: Box<dyn LocalInferenceExecutor>) -> Arc<Self> {
        Arc::new(Self {
            executor: executor.into(),
        })
    }
    /// Creates an independent stream; inline tool sessions are request-scoped.
    pub fn stream(
        &self,
        input: InferenceCompletionInput,
        tools: Option<Arc<LocalToolSession>>,
    ) -> Arc<LocalInferenceStream> {
        LocalInferenceStream::new(self.executor.clone(), input, tools)
    }
}
