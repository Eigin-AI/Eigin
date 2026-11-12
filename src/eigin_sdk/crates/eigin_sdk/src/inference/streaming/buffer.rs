use crate::inference::InferenceError;

const MAX_BYTES: usize = 1024 * 1024;

#[derive(Default)]
pub(super) struct SseBuffer {
    bytes: Vec<u8>,
    skip_lf: bool,
}

impl SseBuffer {
    pub fn line(&mut self) -> Result<Option<Vec<u8>>, InferenceError> {
        if self.skip_lf && !self.bytes.is_empty() {
            if self.bytes[0] == b'\n' {
                self.bytes.remove(0);
            }
            self.skip_lf = false;
        }
        let end = self.bytes.iter().position(|b| *b == b'\n' || *b == b'\r');
        if end.unwrap_or(self.bytes.len()) > MAX_BYTES {
            return Err(InferenceError::LimitExceeded {
                limit: "1 MiB SSE line".into(),
            });
        }
        let Some(end) = end else {
            return Ok(None);
        };
        self.skip_lf = self.bytes[end] == b'\r';
        let mut line: Vec<_> = self.bytes.drain(..=end).collect();
        line.pop();
        Ok(Some(line))
    }

    pub fn push(&mut self, chunk: Vec<u8>) -> Result<(), InferenceError> {
        if chunk.len() > MAX_BYTES {
            return Err(InferenceError::LimitExceeded {
                limit: "1 MiB HTTP chunk".into(),
            });
        }
        self.bytes.extend(chunk);
        Ok(())
    }

    pub fn remaining(&mut self) -> Vec<u8> {
        std::mem::take(&mut self.bytes)
    }
}
