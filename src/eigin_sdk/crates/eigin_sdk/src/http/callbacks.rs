use super::{HttpResponseHead, HttpTransportError};
use std::future::poll_fn;
use std::sync::Mutex;
use std::task::{Poll, Waker};

struct CallbackState<T> {
    completed: bool,
    result: Option<Result<T, HttpTransportError>>,
    waker: Option<Waker>,
}

pub(super) struct CallbackResult<T>(Mutex<CallbackState<T>>);

impl<T> Default for CallbackResult<T> {
    fn default() -> Self {
        Self(Mutex::new(CallbackState {
            completed: false,
            result: None,
            waker: None,
        }))
    }
}

impl<T> CallbackResult<T> {
    pub fn complete(&self, result: Result<T, HttpTransportError>) {
        let waker = {
            let mut state = self.0.lock().unwrap();
            if state.completed {
                return;
            }
            state.completed = true;
            state.result = Some(result);
            state.waker.take()
        };
        if let Some(waker) = waker {
            waker.wake();
        }
    }

    pub async fn wait(&self) -> Result<T, HttpTransportError> {
        poll_fn(|cx| {
            let mut state = self.0.lock().unwrap();
            if let Some(result) = state.result.take() {
                Poll::Ready(result)
            } else {
                state.waker = Some(cx.waker().clone());
                Poll::Pending
            }
        })
        .await
    }
}

/// Single-use callback delivering response status and headers to a waiting Rust operation.
#[derive(Default, uniffi::Object)]
pub struct HttpResponseHeadCallback(pub(super) CallbackResult<HttpResponseHead>);

#[uniffi::export]
impl HttpResponseHeadCallback {
    /// Delivers response headers once. Later completions are ignored.
    pub fn succeed(&self, head: HttpResponseHead) {
        self.0.complete(Ok(head));
    }

    /// Preserves a platform error category for host presentation and routing.
    pub fn fail_with_code(&self, reason: String, domain: String, code: i64) {
        self.0.complete(Err(HttpTransportError::Failed {
            reason,
            domain: Some(domain),
            code: Some(code),
        }));
    }

    /// Fails the pending request/read with a transport error.
    pub fn fail(&self, reason: String) {
        self.0.complete(Err(HttpTransportError::Failed {
            reason,
            domain: None,
            code: None,
        }));
    }
}

/// Single-use callback delivering the next body chunk or end-of-stream.
#[derive(Default, uniffi::Object)]
pub struct HttpBodyChunkCallback(pub(super) CallbackResult<Option<Vec<u8>>>);

#[uniffi::export]
impl HttpBodyChunkCallback {
    /// Delivers one chunk, or None at EOF. Later completions are ignored.
    pub fn succeed(&self, bytes: Option<Vec<u8>>) {
        self.0.complete(Ok(bytes));
    }

    /// Preserves a platform error category for host presentation and routing.
    pub fn fail_with_code(&self, reason: String, domain: String, code: i64) {
        self.0.complete(Err(HttpTransportError::Failed {
            reason,
            domain: Some(domain),
            code: Some(code),
        }));
    }

    /// Fails the pending request/read with a transport error.
    pub fn fail(&self, reason: String) {
        self.0.complete(Err(HttpTransportError::Failed {
            reason,
            domain: None,
            code: None,
        }));
    }
}
