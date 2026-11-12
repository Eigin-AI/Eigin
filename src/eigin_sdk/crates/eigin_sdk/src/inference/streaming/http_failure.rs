use crate::{
    http::{HttpOperation, HttpTransportError},
    inference::{InferenceError, inference_diagnostics::InferenceDiagnostics},
};

pub(crate) struct HttpFailurePolicy {
    pub body_limit: usize,
    /// Stop after complete lines exceed this total character count, excluding line endings.
    pub completed_line_character_limit: Option<usize>,
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
            if let Some(limit) = self.completed_line_character_limit {
                let mut characters = 0;
                let mut end = 0;
                for line in bytes.split_inclusive(|byte| matches!(*byte, b'\r' | b'\n')) {
                    if !matches!(line.last(), Some(b'\r' | b'\n')) {
                        break;
                    }
                    end += line.len();
                    characters += unicode_segmentation::UnicodeSegmentation::graphemes(
                        String::from_utf8_lossy(line).trim_end_matches(['\r', '\n']),
                        true,
                    )
                    .count();
                    if characters > limit {
                        bytes.truncate(end);
                        return (self.normalize)(
                            status,
                            Some(String::from_utf8_lossy(&bytes).into_owned()),
                        );
                    }
                }
            }
        }
        (self.normalize)(
            status,
            (!bytes.is_empty()).then(|| String::from_utf8_lossy(&bytes).into_owned()),
        )
    }
}
