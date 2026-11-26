use super::*;

pub(in super::super) type EventResult = Result<Option<InferenceEvent>, RequestError>;

pub(in super::super) struct Stream {
    pub(in super::super) events: Mutex<VecDeque<EventResult>>,
    pub(in super::super) cancelled: AtomicBool,
    pub(in super::super) stall_at_end: AtomicBool,
    pub(in super::super) pending: Mutex<Option<futures::channel::oneshot::Receiver<EventResult>>>,
}
impl Stream {
    pub(in super::super) fn new(events: Vec<InferenceEvent>) -> Arc<Self> {
        Arc::new(Self {
            events: Mutex::new(events.into_iter().map(|event| Ok(Some(event))).collect()),
            cancelled: AtomicBool::new(false),
            stall_at_end: AtomicBool::new(false),
            pending: Mutex::default(),
        })
    }
}
impl RequestCandidate for Stream {
    fn next(&self) -> BoxFuture<'_, EventResult> {
        async {
            let pending = self.pending.lock().unwrap().take();
            if let Some(pending) = pending {
                return pending.await.unwrap();
            }
            let event = self.events.lock().unwrap().pop_front();
            if event.is_none() && self.stall_at_end.load(Ordering::SeqCst) {
                return std::future::pending().await;
            }
            event.unwrap_or(Ok(None))
        }
        .boxed()
    }
    fn cancel(&self) {
        self.cancelled.store(true, Ordering::SeqCst);
    }
}

#[derive(Default)]
pub(in super::super) struct Effects {
    pub(in super::super) reports: Mutex<Vec<RequestReport>>,
    pub(in super::super) streams: Mutex<HashMap<String, Arc<Stream>>>,
    pub(in super::super) opens: Mutex<Vec<String>>,
    pub(in super::super) log: Mutex<Vec<String>>,
    pub(in super::super) ranking: Mutex<VecDeque<String>>,
    pub(in super::super) failed_prepare: Mutex<Vec<String>>,
    pub(in super::super) preparing: Mutex<HashMap<String, futures::channel::oneshot::Receiver<()>>>,
    pub(in super::super) opening: Mutex<HashMap<String, futures::channel::oneshot::Receiver<()>>>,
    pub(in super::super) cancelled: Mutex<Vec<u64>>,
    pub(in super::super) cancel_on_prepare: Mutex<Option<(String, Arc<RequestCancellation>)>>,
}
impl RequestEffects for Effects {
    fn prepare(
        &self,
        _id: u64,
        model: String,
    ) -> BoxFuture<'_, Result<Option<crate::model_catalog::CatalogReasoningEffort>, RequestError>>
    {
        async move {
            self.log.lock().unwrap().push(format!("prepare:{model}"));
            let wait = self.preparing.lock().unwrap().remove(&model);
            if let Some(wait) = wait {
                let _ = wait.await;
            }
            let stop = self.cancel_on_prepare.lock().unwrap().clone();
            if let Some((target, stop)) = stop
                && target == model
            {
                stop.cancel();
            }
            if self.failed_prepare.lock().unwrap().contains(&model) {
                Err(InferenceError::InvalidData {
                    reason: "context too large".into(),
                }
                .into())
            } else {
                Ok(None)
            }
        }
        .boxed()
    }
    fn open(
        &self,
        _id: u64,
        model: String,
        _effort: Option<crate::model_catalog::CatalogReasoningEffort>,
    ) -> BoxFuture<'_, Result<Arc<dyn RequestCandidate>, RequestError>> {
        async move {
            self.log.lock().unwrap().push(format!("open:{model}"));
            self.opens.lock().unwrap().push(model.clone());
            let wait = self.opening.lock().unwrap().remove(&model);
            if let Some(wait) = wait {
                let _ = wait.await;
            }
            self.streams
                .lock()
                .unwrap()
                .get(&model)
                .cloned()
                .map(|stream| stream as Arc<dyn RequestCandidate>)
                .ok_or_else(|| RequestError::Classified {
                    error: InferenceError::Http {
                        status: 404,
                        body: Some("model not found".into()),
                    },
                    failure: crate::inference::routing::RoutingFailure::ModelNotFound,
                })
        }
        .boxed()
    }
    fn cancel(&self, id: u64) {
        self.cancelled.lock().unwrap().push(id);
    }
    fn record_failure(&self, model: String, _error: RequestError) {
        self.log.lock().unwrap().push(format!("failure:{model}"));
    }
    fn refresh_catalog(&self) -> BoxFuture<'_, ()> {
        async {
            self.log.lock().unwrap().push("refresh".into());
        }
        .boxed()
    }
    fn rank_replacement(
        &self,
        model: String,
        _error: RequestError,
    ) -> BoxFuture<'_, Option<String>> {
        async move {
            self.log.lock().unwrap().push(format!("rank:{model}"));
            self.ranking.lock().unwrap().pop_front()
        }
        .boxed()
    }
    fn record_loser(&self, model: String, _silent_ms: u64) {
        self.log.lock().unwrap().push(format!("loser:{model}"));
    }
    fn record_outcome(&self, report: RequestReport) {
        self.reports.lock().unwrap().push(report);
    }
}
pub(in super::super) fn options() -> RequestOptions {
    RequestOptions {
        model: "primary".into(),
        local: false,
        routed: true,
        hedge: None,
        ceiling_ms: 60_000,
        max_buffered_bytes: 1_048_576,
    }
}
pub(in super::super) fn text(value: &str) -> InferenceEvent {
    InferenceEvent::ContentDelta { text: value.into() }
}
pub(in super::super) fn finish() -> InferenceEvent {
    InferenceEvent::Finished {
        reason: InferenceFinishReason::Stop,
    }
}
pub(in super::super) fn effects(model: &str, events: Vec<InferenceEvent>) -> Arc<Effects> {
    let effects = Arc::new(Effects::default());
    effects
        .streams
        .lock()
        .unwrap()
        .insert(model.into(), Stream::new(events));
    effects
}
