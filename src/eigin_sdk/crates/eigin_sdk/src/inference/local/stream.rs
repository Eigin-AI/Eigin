use super::*;
use std::sync::Arc;
use std::sync::{
    Mutex,
    atomic::{AtomicU64, Ordering},
};

static NEXT_ID: AtomicU64 = AtomicU64::new(1);

enum Pending {
    Open(Arc<LocalOpenCallback>),
    Event(Arc<LocalEventCallback>),
}

impl Pending {
    fn cancel(&self) {
        match self {
            Self::Open(c) => c.0.complete(Err(InferenceError::Cancelled)),
            Self::Event(c) => c.0.complete(Err(InferenceError::Cancelled)),
        }
    }
}

#[derive(Default)]
struct State {
    opened: bool,
    eof: bool,
    closed: bool,
    dispatching: bool,
    pending: Option<Pending>,
}

/// A host inference operation. Cancellation wakes pending foreign futures.
#[derive(uniffi::Object)]
pub struct LocalInferenceStream {
    id: u64,
    executor: Arc<dyn LocalInferenceExecutor>,
    state: Mutex<State>,
    input: Mutex<Option<InferenceCompletionInput>>,
    tools: Option<Arc<LocalToolSession>>,
}

impl LocalInferenceStream {
    pub(super) fn new(
        executor: Arc<dyn LocalInferenceExecutor>,
        input: InferenceCompletionInput,
        tools: Option<Arc<LocalToolSession>>,
    ) -> Arc<Self> {
        Arc::new(Self {
            id: NEXT_ID.fetch_add(1, Ordering::Relaxed),
            executor,
            state: Mutex::new(State::default()),
            input: Mutex::new(Some(input)),
            tools,
        })
    }

    fn dispatch(
        &self,
        pending: Pending,
        opening: bool,
        call: impl FnOnce(),
    ) -> Result<(), InferenceError> {
        {
            let mut state = self.state.lock().unwrap();
            if state.closed {
                return Err(InferenceError::Cancelled);
            }
            if state.pending.is_some() || (opening && state.opened) || (!opening && !state.opened) {
                return Err(InferenceError::Busy);
            }
            if opening {
                state.opened = true;
            }
            state.pending = Some(pending);
            state.dispatching = true;
        }
        call();
        let closed = {
            let mut state = self.state.lock().unwrap();
            state.dispatching = false;
            state.closed
        };
        // Cancellation racing with dispatch closes after the host registered the ID.
        if closed {
            self.executor.close(self.id);
        }
        Ok(())
    }
}

#[uniffi::export]
impl LocalInferenceStream {
    /// Prepares the host runtime once. Concurrent calls return Busy.
    pub async fn open(&self) -> Result<(), InferenceError> {
        let completion = Arc::new(LocalOpenCallback::default());
        self.dispatch(Pending::Open(completion.clone()), true, || {
            let input = self.input.lock().unwrap().take().unwrap();
            self.executor
                .start_request(self.id, input, self.tools.clone(), completion.clone())
        })?;
        let mut guard = PendingGuard {
            operation: self,
            completed: false,
        };
        let result = completion.0.wait().await;
        guard.completed = result.is_ok();
        if self.state.lock().unwrap().closed {
            return Err(InferenceError::Cancelled);
        }
        result
    }

    /// Reads one ordered inference event, releasing host resources at EOF.
    pub async fn next(&self) -> Result<Option<InferenceEvent>, InferenceError> {
        if self.state.lock().unwrap().eof {
            return Ok(None);
        }
        let completion = Arc::new(LocalEventCallback::default());
        self.dispatch(Pending::Event(completion.clone()), false, || {
            self.executor.read(self.id, completion.clone())
        })?;
        let mut guard = PendingGuard {
            operation: self,
            completed: false,
        };
        let result = completion.0.wait().await;
        guard.completed = result.is_ok();
        if self.state.lock().unwrap().closed {
            return Err(InferenceError::Cancelled);
        }
        if matches!(result, Ok(None)) {
            self.state.lock().unwrap().eof = true;
            self.cancel();
        }
        result
    }

    /// Cancels native generation and inline tool execution. Safe to repeat.
    pub fn cancel(&self) {
        let (pending, close) = {
            let mut state = self.state.lock().unwrap();
            if state.closed {
                return;
            }
            state.closed = true;
            (state.pending.take(), !state.dispatching)
        };
        if let Some(tools) = &self.tools {
            tools.cancel();
        }
        if let Some(pending) = pending {
            pending.cancel();
        }
        if close {
            self.executor.close(self.id);
        }
    }
}

impl Drop for LocalInferenceStream {
    fn drop(&mut self) {
        self.cancel();
    }
}

struct PendingGuard<'a> {
    operation: &'a LocalInferenceStream,
    completed: bool,
}

impl Drop for PendingGuard<'_> {
    fn drop(&mut self) {
        self.operation.state.lock().unwrap().pending = None;
        if !self.completed {
            self.operation.cancel();
        }
    }
}
