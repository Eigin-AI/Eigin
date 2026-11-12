use crate::{
    http::{HttpOperation, HttpTransportError},
    inference::{InferenceError, inference_diagnostics::InferenceDiagnostics},
};

pub(crate) struct HttpFailurePolicy {
    pub body_limit: usize,
    pub retain_partial_body: bool,
    pub normalize: fn(u16, Option<String>) -> InferenceError,
}

impl HttpFailurePolicy {
    pub async fn read(
        &self,
        http: &HttpOperation,
        status: u16,
        diagnostics: &InferenceDiagnostics,
    ) -> InferenceError {
        let mut bytes = Vec::new();
        while bytes.len() < self.body_limit {
            let chunk = match http.read().await {
                Ok(Some(chunk)) => chunk,
                Ok(None) => break,
                Err(HttpTransportError::Cancelled) => return InferenceError::Cancelled,
                Err(_) if self.retain_partial_body => break,
                Err(error) => return error.into(),
            };
            diagnostics.chunk(chunk.len());
            bytes.extend(chunk.into_iter().take(self.body_limit - bytes.len()));
        }
        (self.normalize)(
            status,
            (!bytes.is_empty()).then(|| String::from_utf8_lossy(&bytes).into_owned()),
        )
    }
}
