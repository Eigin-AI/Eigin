use super::RequestError;
use crate::inference::InferenceError;
use std::{
    future::poll_fn,
    sync::Mutex,
    task::{Poll, Waker},
};

pub(crate) trait Pending: Send + Sync {
    fn cancel(&self);
}

struct State<T> {
    completed: bool,
    result: Option<Result<T, RequestError>>,
    waker: Option<Waker>,
}

pub(crate) struct Completion<T>(Mutex<State<T>>);
impl<T> Default for Completion<T> {
    fn default() -> Self {
        Self(Mutex::new(State {
            completed: false,
            result: None,
            waker: None,
        }))
    }
}

impl<T> Completion<T> {
    pub fn complete(&self, result: Result<T, RequestError>) -> bool {
        let wake = {
            let mut state = self.0.lock().unwrap();
            if state.completed {
                return false;
            }
            state.completed = true;
            state.result = Some(result);
            state.waker.take()
        };
        if let Some(wake) = wake {
            wake.wake();
        }
        true
    }

    pub async fn wait(&self) -> Result<T, RequestError> {
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

impl<T: Send> Pending for Completion<T> {
    fn cancel(&self) {
        let wake = {
            let mut state = self.0.lock().unwrap();
            state.completed = true;
            state.result = Some(Err(InferenceError::Cancelled.into()));
            state.waker.take()
        };
        if let Some(wake) = wake {
            wake.wake();
        }
    }
}
