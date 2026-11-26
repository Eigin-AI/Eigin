use super::*;

/// Schedules host work without blocking the Rust runtime or stop/checkpoint calls.
#[uniffi::export(callback_interface)]
pub trait TurnHost: Send + Sync {
    fn prepare(
        &self,
        operation_id: u64,
        context: TurnContext,
        inline: Arc<InlineTurnOperation>,
        completion: Arc<TurnPrepareCallback>,
    );
    fn notify(&self, operation_id: u64, event: ChatTurnEvent, completion: Arc<TurnNotifyCallback>);
    fn present(
        &self,
        operation_id: u64,
        work: TurnPresentation,
        completion: Arc<TurnNotifyCallback>,
    );
    fn execute(
        &self,
        operation_id: u64,
        call: InferenceToolCall,
        completion: Arc<TurnToolCallback>,
    );
    fn refresh_tools(&self, operation_id: u64, completion: Arc<TurnToolsCallback>);
    fn signals(
        &self,
        operation_id: u64,
        boundary: TurnSignalBoundary,
        completion: Arc<TurnSignalsCallback>,
    );
    fn classify_failure(&self, error: RequestError) -> TurnFailure;
    fn cancel_operation(&self, operation_id: u64);
}

#[derive(Default)]
struct Calls {
    closed: bool,
    pending: HashMap<u64, PendingCall>,
}
struct PendingCall {
    completion: Arc<dyn Pending>,
    retain_result: bool,
}
static NEXT_OPERATION: AtomicU64 = AtomicU64::new(1);

pub(super) struct Host {
    host: Arc<dyn TurnHost>,
    calls: Mutex<Calls>,
}
impl Host {
    pub fn new(host: Box<dyn TurnHost>) -> Arc<Self> {
        Arc::new(Self {
            host: host.into(),
            calls: Mutex::default(),
        })
    }

    async fn call<T: Send + 'static>(
        &self,
        completion: Arc<Completion<T>>,
        retain_result: bool,
        dispatch: impl FnOnce(u64),
    ) -> Result<T, RequestError> {
        let id = NEXT_OPERATION.fetch_add(1, Ordering::Relaxed);
        {
            let mut calls = self.calls.lock().unwrap();
            if calls.closed {
                return Err(InferenceError::Cancelled.into());
            }
            calls.pending.insert(
                id,
                PendingCall {
                    completion: completion.clone(),
                    retain_result,
                },
            );
        }
        let _guard = Call {
            host: self,
            id,
            completion: completion.clone(),
        };
        dispatch(id);
        if !self.calls.lock().unwrap().pending.contains_key(&id) {
            self.host.cancel_operation(id);
        }
        completion.wait().await
    }

    pub fn close(&self) {
        let calls = {
            let mut calls = self.calls.lock().unwrap();
            calls.closed = true;
            std::mem::take(&mut calls.pending)
        };
        for (id, pending) in calls {
            if !pending.retain_result {
                pending.completion.cancel();
            }
            self.host.cancel_operation(id);
        }
    }
}
struct Call<'a> {
    host: &'a Host,
    id: u64,
    completion: Arc<dyn Pending>,
}
impl Drop for Call<'_> {
    fn drop(&mut self) {
        self.host.calls.lock().unwrap().pending.remove(&self.id);
        self.completion.cancel();
        self.host.host.cancel_operation(self.id);
    }
}

impl ChatTurnHost for Host {
    fn prepare(
        &self,
        context: TurnContext,
        inline: Arc<InlineTurnTools>,
    ) -> BoxFuture<'_, Result<PreparedTurnRequest, RequestError>> {
        async move {
            let callback = Arc::new(TurnPrepareCallback::default());
            self.call(callback.0.clone(), false, |id| {
                self.host
                    .prepare(id, context, Arc::new(InlineTurnOperation(inline)), callback)
            })
            .await
        }
        .boxed()
    }
    fn notify(&self, event: ChatTurnEvent) -> BoxFuture<'_, ()> {
        async move {
            let callback = Arc::new(TurnNotifyCallback::default());
            let _ = self
                .call(callback.0.clone(), false, |id| {
                    self.host.notify(id, event, callback)
                })
                .await;
        }
        .boxed()
    }
    fn present(&self, work: TurnPresentation) -> BoxFuture<'_, ()> {
        async move {
            let callback = Arc::new(TurnNotifyCallback::default());
            let _ = self
                .call(callback.0.clone(), false, |id| {
                    self.host.present(id, work, callback)
                })
                .await;
        }
        .boxed()
    }
    fn execute(&self, call: InferenceToolCall) -> BoxFuture<'_, LocalToolResult> {
        async move {
            let callback = Arc::new(TurnToolCallback::default());
            let cancelled = LocalToolResult {
                tool_call_id: call.id.clone(),
                content: "{}".into(),
                is_error: true,
            };
            self.call(callback.0.clone(), true, |id| {
                self.host.execute(id, call, callback)
            })
            .await
            .unwrap_or(cancelled)
        }
        .boxed()
    }
    fn refresh_tools(&self) -> BoxFuture<'_, Option<Vec<InferenceToolDefinition>>> {
        async move {
            let callback = Arc::new(TurnToolsCallback::default());
            self.call(callback.0.clone(), false, |id| {
                self.host.refresh_tools(id, callback)
            })
            .await
            .unwrap_or(None)
        }
        .boxed()
    }
    fn signals(&self, boundary: TurnSignalBoundary) -> BoxFuture<'_, TurnSignals> {
        async move {
            let callback = Arc::new(TurnSignalsCallback::default());
            self.call(callback.0.clone(), false, |id| {
                self.host.signals(id, boundary, callback)
            })
            .await
            .unwrap_or(TurnSignals {
                cancelled: true,
                stopped: false,
                terminate: false,
            })
        }
        .boxed()
    }
    fn classify_failure(&self, error: &RequestError) -> TurnFailure {
        self.host.classify_failure(error.clone())
    }
}
