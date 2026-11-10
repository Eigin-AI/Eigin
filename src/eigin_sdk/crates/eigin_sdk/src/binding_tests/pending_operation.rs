//! Host-controlled pending operations for binding contracts.

use std::future::poll_fn;
use std::sync::{Arc, Mutex};
use std::task::{Poll, Waker};

/// A predictable failure for host contract tests.
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum BindingTestError {
    /// Preserves a numeric code and text across the binding boundary.
    #[error("{code}: {reason}")]
    Rejected { code: u32, reason: String },
}

#[derive(Default)]
struct State {
    started: bool,
    pending: bool,
    completed: bool,
    result: Option<Result<String, BindingTestError>>,
    operation: Option<Waker>,
    observers: Vec<Waker>,
}

/// An operation completed explicitly by the host, without timers or blocking.
#[derive(Default, uniffi::Object)]
pub struct PendingOperation {
    state: Mutex<State>,
}

#[uniffi::export]
impl PendingOperation {
    /// Creates an independent, single-use operation.
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }

    /// Waits for host completion; a repeated call returns a fixture error.
    pub async fn run(&self) -> Result<String, BindingTestError> {
        {
            let mut state = self.state.lock().unwrap();
            if state.started {
                return Err(BindingTestError::Rejected {
                    code: 0,
                    reason: "operation already started".into(),
                });
            }
            state.started = true;
        }
        poll_fn(|context| {
            let observers = {
                let mut state = self.state.lock().unwrap();
                if let Some(result) = state.result.take() {
                    return Poll::Ready(result);
                }
                state.operation = Some(context.waker().clone());
                state.pending = true;
                std::mem::take(&mut state.observers)
            };
            for observer in observers {
                observer.wake();
            }
            Poll::Pending
        })
        .await
    }

    /// Resolves once run has registered its waker and suspended.
    pub async fn wait_until_pending(&self) {
        poll_fn(|context| {
            let mut state = self.state.lock().unwrap();
            if state.pending {
                Poll::Ready(())
            } else {
                if !state.observers.iter().any(|w| w.will_wake(context.waker())) {
                    state.observers.push(context.waker().clone());
                }
                Poll::Pending
            }
        })
        .await
    }

    /// Completes with a value; only the first completion takes effect.
    pub fn succeed(&self, value: String) {
        self.complete(Ok(value));
    }

    /// Completes with a typed error; only the first completion takes effect.
    pub fn fail(&self, code: u32, reason: String) {
        self.complete(Err(BindingTestError::Rejected { code, reason }));
    }
}

impl PendingOperation {
    fn complete(&self, result: Result<String, BindingTestError>) {
        let operation = {
            let mut state = self.state.lock().unwrap();
            if state.completed {
                return;
            }
            state.completed = true;
            state.result = Some(result);
            state.operation.take()
        };
        if let Some(operation) = operation {
            operation.wake();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures::{FutureExt, executor::block_on, task::ArcWake};
    use std::sync::atomic::{AtomicUsize, Ordering};

    #[derive(Default)]
    struct WakeCount(AtomicUsize);

    impl ArcWake for WakeCount {
        fn wake_by_ref(arc_self: &Arc<Self>) {
            arc_self.0.fetch_add(1, Ordering::SeqCst);
        }
    }

    #[test]
    fn pending_operation_wakes_observer_and_resumes_with_payload() {
        let operation = PendingOperation::new();
        let count = Arc::new(WakeCount::default());
        let waker = futures::task::waker(count.clone());
        let mut context = std::task::Context::from_waker(&waker);
        let mut ready = Box::pin(operation.wait_until_pending());
        assert!(ready.as_mut().poll(&mut context).is_pending());
        let mut result = Box::pin(operation.run());
        assert!(result.as_mut().poll(&mut context).is_pending());
        assert_eq!(count.0.load(Ordering::SeqCst), 1);
        assert!(ready.as_mut().poll(&mut context).is_ready());
        block_on(operation.wait_until_pending());
        operation.fail(42, "boundary payload".into());
        assert_eq!(count.0.load(Ordering::SeqCst), 2);
        assert!(
            matches!(block_on(result), Err(BindingTestError::Rejected { code: 42, reason }) if reason == "boundary payload")
        );
    }

    #[test]
    fn completion_is_retained_and_first_completion_wins() {
        let operation = PendingOperation::new();
        operation.succeed("first".into());
        operation.fail(42, "ignored".into());
        assert_eq!(block_on(operation.run()).unwrap(), "first");
        assert!(matches!(
            block_on(operation.run()),
            Err(BindingTestError::Rejected { code: 0, .. })
        ));
    }

    #[test]
    fn operations_complete_independently() {
        let first = PendingOperation::new();
        let second = PendingOperation::new();
        let mut first_run = Box::pin(first.run());
        let mut second_run = Box::pin(second.run());
        assert!(first_run.as_mut().now_or_never().is_none());
        assert!(second_run.as_mut().now_or_never().is_none());
        first.succeed("first".into());
        assert_eq!(block_on(first_run).unwrap(), "first");
        assert!(second_run.as_mut().now_or_never().is_none());
        second.succeed("second".into());
        assert_eq!(block_on(second_run).unwrap(), "second");
    }
}
