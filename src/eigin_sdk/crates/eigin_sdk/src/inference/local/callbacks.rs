use super::{InferenceError, InferenceEvent, LocalToolResult};
use std::{
    future::poll_fn,
    sync::Mutex,
    task::{Poll, Waker},
};

struct CompletionState<T> {
    completed: bool,
    result: Option<Result<T, InferenceError>>,
    waker: Option<Waker>,
}

pub(super) struct Completion<T>(Mutex<CompletionState<T>>);
impl<T> Default for Completion<T> {
    fn default() -> Self {
        Self(Mutex::new(CompletionState {
            completed: false,
            result: None,
            waker: None,
        }))
    }
}
impl<T> Completion<T> {
    pub fn complete(&self, result: Result<T, InferenceError>) {
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
    pub async fn wait(&self) -> Result<T, InferenceError> {
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

/// Single-use completion for host runtime preparation.
#[derive(Default, uniffi::Object)]
pub struct LocalOpenCallback(pub(super) Completion<()>);
#[uniffi::export]
impl LocalOpenCallback {
    /// Completes the pending operation once; later completions are ignored.
    pub fn succeed(&self) {
        self.0.complete(Ok(()));
    }
    /// Fails the pending operation with a typed inference error.
    pub fn fail(&self, error: InferenceError) {
        self.0.complete(Err(error));
    }
}

/// Single-use completion delivering one ordered event, or end-of-stream.
#[derive(Default, uniffi::Object)]
pub struct LocalEventCallback(pub(super) Completion<Option<InferenceEvent>>);
#[uniffi::export]
impl LocalEventCallback {
    /// Completes the pending operation once; later completions are ignored.
    pub fn succeed(&self, event: Option<InferenceEvent>) {
        self.0.complete(Ok(event));
    }
    /// Fails the pending operation with a typed inference error.
    pub fn fail(&self, error: InferenceError) {
        self.0.complete(Err(error));
    }
}

/// Single-use completion for inline tool execution.
#[derive(Default, uniffi::Object)]
pub struct LocalToolCallback(pub(super) Completion<LocalToolResult>);
#[uniffi::export]
impl LocalToolCallback {
    /// Completes the pending operation once; later completions are ignored.
    pub fn succeed(&self, result: LocalToolResult) {
        self.0.complete(Ok(result));
    }
    /// Fails the pending operation with a typed inference error.
    pub fn fail(&self, error: InferenceError) {
        self.0.complete(Err(error));
    }
}
