use super::*;

pub(super) type Event = Result<Option<InferenceEvent>, RequestError>;
pub(super) struct Script {
    pub(super) events: Vec<InferenceEvent>,
    pub(super) error: Option<RequestError>,
    pub(super) inline: Vec<InferenceToolCall>,
}
impl Script {
    pub(super) fn events(events: Vec<InferenceEvent>) -> Self {
        Self {
            events,
            error: None,
            inline: vec![],
        }
    }
}
#[derive(Default)]
pub(super) struct Host {
    pub(super) scripts: Mutex<VecDeque<Script>>,
    pub(super) reports: Arc<Mutex<Vec<crate::inference::routing::RoutingResult>>>,
    pub(super) contexts: Mutex<Vec<TurnContext>>,
    pub(super) events: Mutex<Vec<ChatTurnEvent>>,
    pub(super) calls: Mutex<Vec<String>>,
    pub(super) waits: Mutex<HashMap<String, oneshot::Receiver<()>>>,
    pub(super) inline: Mutex<Vec<Arc<InlineTurnTools>>>,
    pub(super) refreshes: AtomicUsize,
    pub(super) local: AtomicBool,
    pub(super) terminate: AtomicBool,
    pub(super) next_wait: Mutex<Option<oneshot::Receiver<()>>>,
    pub(super) prepare_wait: Mutex<Option<oneshot::Receiver<()>>>,
    pub(super) drain_wait: Mutex<Option<oneshot::Receiver<()>>>,
    pub(super) reenter_on_cancel: AtomicBool,
}
impl ChatTurnHost for Host {
    fn prepare(
        &self,
        context: TurnContext,
        inline: Arc<InlineTurnTools>,
    ) -> BoxFuture<'_, Result<PreparedTurnRequest, RequestError>> {
        async move {
            self.contexts.lock().unwrap().push(context);
            self.inline.lock().unwrap().push(inline.clone());
            let wait = self.prepare_wait.lock().unwrap().take();
            if let Some(wait) = wait {
                let _ = wait.await;
            }
            let script = self
                .scripts
                .lock()
                .unwrap()
                .pop_front()
                .expect("unexpected request");
            let mut events: VecDeque<Event> = script
                .events
                .into_iter()
                .map(|event| Ok(Some(event)))
                .collect();
            events.push_back(script.error.map_or(Ok(None), Err));
            Ok(PreparedTurnRequest {
                provider_id: "provider".into(),
                local: self.local.load(Ordering::SeqCst),
                routing: None,
                platform: Arc::new(Platform(Arc::new(Candidate {
                    events: Mutex::new(events),
                    reports: self.reports.clone(),
                    tools: Mutex::new(script.inline),
                    inline,
                    cancelled: AtomicBool::new(false),
                    wait: Mutex::new(self.next_wait.lock().unwrap().take()),
                    reenter_on_cancel: self.reenter_on_cancel.load(Ordering::SeqCst),
                }))),
            })
        }
        .boxed()
    }
    fn notify(&self, event: ChatTurnEvent) -> BoxFuture<'_, ()> {
        async move {
            self.events.lock().unwrap().push(event);
        }
        .boxed()
    }
    fn present(&self, work: TurnPresentation) -> BoxFuture<'_, ()> {
        async move {
            let drain = matches!(work, TurnPresentation::Drain);
            if drain {
                let wait = self.drain_wait.lock().unwrap().take();
                if let Some(wait) = wait {
                    let _ = wait.await;
                }
            }
        }
        .boxed()
    }
    fn execute(&self, call: InferenceToolCall) -> BoxFuture<'_, LocalToolResult> {
        async move {
            self.calls.lock().unwrap().push(call.id.clone());
            let wait = self.waits.lock().unwrap().remove(&call.id);
            if let Some(wait) = wait {
                let _ = wait.await;
            }
            LocalToolResult {
                tool_call_id: call.id,
                content: "result".into(),
                is_error: false,
            }
        }
        .boxed()
    }
    fn refresh_tools(&self) -> BoxFuture<'_, Option<Vec<InferenceToolDefinition>>> {
        async move {
            self.refreshes.fetch_add(1, Ordering::SeqCst);
            Some(vec![InferenceToolDefinition {
                name: "refreshed".into(),
                description: "".into(),
                parameters_json: "{}".into(),
            }])
        }
        .boxed()
    }
    fn signals(&self, _: TurnSignalBoundary) -> BoxFuture<'_, TurnSignals> {
        async {
            TurnSignals {
                terminate: self.terminate.load(Ordering::SeqCst),
                ..Default::default()
            }
        }
        .boxed()
    }
    fn classify_failure(&self, error: &RequestError) -> TurnFailure {
        match error {
            RequestError::Inference(InferenceError::Interrupted) => TurnFailure::Interruption,
            _ => TurnFailure::Terminal,
        }
    }
}
pub(super) struct Platform(Arc<Candidate>);
impl RequestPlatform for Platform {
    fn reported(
        &self,
        _: Option<crate::inference::request_driver::RequestReport>,
        result: crate::inference::routing::RoutingResult,
    ) {
        self.0.reports.lock().unwrap().push(result);
    }
    fn validate(&self, _: u64, _: String) -> BoxFuture<'_, Result<(), RequestError>> {
        async { Ok(()) }.boxed()
    }
    fn open(
        &self,
        _: u64,
        _: String,
        _: Option<CatalogReasoningEffort>,
    ) -> BoxFuture<'_, Result<Arc<dyn RequestCandidate>, RequestError>> {
        async { Ok(self.0.clone() as Arc<dyn RequestCandidate>) }.boxed()
    }
    fn cancel(&self, _: u64) {
        self.0.cancel();
    }
    fn refresh_catalog(&self, _: String) -> BoxFuture<'_, Option<RoutingInventory>> {
        async { None }.boxed()
    }
    fn refresh_health(&self, _: String) -> BoxFuture<'_, Vec<RoutingRemoteHealth>> {
        async { vec![] }.boxed()
    }
    fn wall_time(&self) -> f64 {
        0.0
    }
}
pub(super) struct Candidate {
    pub(super) reports: Arc<Mutex<Vec<crate::inference::routing::RoutingResult>>>,
    pub(super) events: Mutex<VecDeque<Event>>,
    pub(super) tools: Mutex<Vec<InferenceToolCall>>,
    pub(super) inline: Arc<InlineTurnTools>,
    pub(super) cancelled: AtomicBool,
    pub(super) wait: Mutex<Option<oneshot::Receiver<()>>>,
    pub(super) reenter_on_cancel: bool,
}
impl RequestCandidate for Candidate {
    fn next(&self) -> BoxFuture<'_, Event> {
        async {
            let wait = self.wait.lock().unwrap().take();
            if let Some(wait) = wait {
                let _ = wait.await;
            }
            let tools = std::mem::take(&mut *self.tools.lock().unwrap());
            for call in tools {
                self.inline.execute(call).await;
            }
            self.events.lock().unwrap().pop_front().unwrap_or(Ok(None))
        }
        .boxed()
    }
    fn cancel(&self) {
        if !self.cancelled.swap(true, Ordering::SeqCst) && self.reenter_on_cancel {
            let result = self.inline.execute(call("cancel-reentry")).now_or_never();
            assert!(result.is_some_and(|result| result.is_error));
        }
    }
}
pub(super) fn text(value: &str) -> InferenceEvent {
    InferenceEvent::ContentDelta { text: value.into() }
}
pub(super) fn finish() -> InferenceEvent {
    InferenceEvent::Finished {
        reason: InferenceFinishReason::Stop,
    }
}
pub(super) fn call(id: &str) -> InferenceToolCall {
    InferenceToolCall {
        id: id.into(),
        kind: "function".into(),
        name: "lookup".into(),
        arguments: "{}".into(),
    }
}
pub(super) fn batch(ids: &[&str]) -> Script {
    let mut events: Vec<_> = ids
        .iter()
        .map(|id| InferenceEvent::ToolCall { call: call(id) })
        .collect();
    events.push(InferenceEvent::Finished {
        reason: InferenceFinishReason::ToolCalls,
    });
    Script::events(events)
}
pub(super) fn operation(host: Arc<dyn ChatTurnHost>) -> Arc<ChatTurn> {
    ChatTurn::new(
        ChatTurnInput {
            messages: vec![],
            tools: None,
            model: "model".into(),
            initial_instruction: None,
            allow_interruption_recovery: true,
            propagate_stream_cancellation: false,
        },
        ModelRouter::new(),
        host,
    )
}
