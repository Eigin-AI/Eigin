use super::*;
use std::sync::{Arc, Mutex};

/// Inline result, including the host's error classification.
#[derive(Clone, Debug, uniffi::Record)]
pub struct LocalToolResult {
    pub tool_call_id: String,
    pub content: String,
    pub is_error: bool,
}

/// Request-scoped host permissions, tool execution, and exchange recording.
#[uniffi::export(callback_interface)]
pub trait LocalToolExecutor: Send + Sync {
    fn execute(&self, call: InferenceToolCall, completion: Arc<LocalToolCallback>);
    /// Cancels pending execution and releases request-scoped state. Safe to repeat.
    fn cancel(&self);
}

#[derive(Default)]
struct ToolState {
    cancelled: bool,
    dispatching: bool,
    pending: Option<Arc<LocalToolCallback>>,
}

/// One inference request's inline tool handler. Create a fresh handle for each stream.
#[derive(uniffi::Object)]
pub struct LocalToolSession {
    executor: Arc<dyn LocalToolExecutor>,
    state: Mutex<ToolState>,
}

#[uniffi::export]
impl LocalToolSession {
    #[uniffi::constructor]
    pub fn new(executor: Box<dyn LocalToolExecutor>) -> Arc<Self> {
        Arc::new(Self {
            executor: executor.into(),
            state: Mutex::default(),
        })
    }

    /// Executes one call without holding SDK locks across host callbacks.
    pub async fn execute(
        &self,
        call: InferenceToolCall,
    ) -> Result<LocalToolResult, InferenceError> {
        let completion = Arc::new(LocalToolCallback::default());
        {
            let mut state = self.state.lock().unwrap();
            if state.cancelled {
                return Err(InferenceError::Cancelled);
            }
            if state.pending.is_some() {
                return Err(InferenceError::Busy);
            }
            state.pending = Some(completion.clone());
            state.dispatching = true;
        }
        self.executor.execute(call, completion.clone());
        let cancelled = {
            let mut state = self.state.lock().unwrap();
            state.dispatching = false;
            state.cancelled
        };
        if cancelled {
            self.executor.cancel();
        }
        let mut guard = ToolGuard {
            session: self,
            completed: false,
        };
        let result = completion.0.wait().await;
        guard.completed = true;
        if self.state.lock().unwrap().cancelled {
            return Err(InferenceError::Cancelled);
        }
        result
    }

    /// Stops inline work and wakes any waiting runtime callback.
    pub fn cancel(&self) {
        let (pending, dispatching) = {
            let mut state = self.state.lock().unwrap();
            if state.cancelled {
                return;
            }
            state.cancelled = true;
            (state.pending.take(), state.dispatching)
        };
        if let Some(pending) = pending {
            pending.fail(InferenceError::Cancelled);
        }
        if !dispatching {
            self.executor.cancel();
        }
    }
}

struct ToolGuard<'a> {
    session: &'a LocalToolSession,
    completed: bool,
}
impl Drop for ToolGuard<'_> {
    fn drop(&mut self) {
        self.session.state.lock().unwrap().pending = None;
        if !self.completed {
            self.session.cancel();
        }
    }
}
impl Drop for LocalToolSession {
    fn drop(&mut self) {
        self.cancel();
    }
}
