#[path = "actions.rs"]
mod actions;
#[path = "reporting.rs"]
mod reporting;
use reporting::Measurements;
pub use reporting::RequestReport;

use super::{
    RequestCancellation, RequestEffects, RequestError, RequestOptions,
    cancellation::CancelOnDrop,
    events,
    work::{self, Candidate, Work},
};
use crate::{
    clock,
    inference::{
        AttemptAction as Action, AttemptObservation as Observation, InferenceAttempts,
        InferenceError, InferenceEvent,
    },
};
use futures_util::{
    FutureExt, StreamExt,
    future::{AbortHandle, Abortable, BoxFuture, Either, select},
    stream::FuturesUnordered,
};
use std::{
    collections::{HashMap, VecDeque},
    sync::Arc,
    time::Duration,
};

/// Consumes candidate streams and owns the race, buffering, and replacement sequence.
/// One caller reads at a time; dropping a pending read cancels the request.
pub struct InferenceRequest {
    clock: Arc<dyn clock::ExecutionClock>,
    policy: Arc<InferenceAttempts>,
    effects: Arc<dyn RequestEffects>,
    cancellation: Arc<RequestCancellation>,
    tasks: FuturesUnordered<BoxFuture<'static, Option<Work>>>,
    aborts: HashMap<u64, AbortHandle>,
    streams: HashMap<u64, Arc<Candidate>>,
    models: HashMap<u64, String>,
    buffers: HashMap<u64, Vec<InferenceEvent>>,
    errors: HashMap<u64, RequestError>,
    output: VecDeque<InferenceEvent>,
    started: Duration,
    measurements: Measurements,
    hedge_opened: Option<Duration>,
    finished: Option<Option<RequestError>>,
    local: bool,
}

impl InferenceRequest {
    /// Opens local inference immediately; cloud dispatch starts when the request is consumed.
    pub async fn open(
        options: RequestOptions,
        effects: Arc<dyn RequestEffects>,
    ) -> Result<Self, RequestError> {
        Self::open_at(options, effects, clock::now()).await
    }

    pub(super) async fn open_at(
        options: RequestOptions,
        effects: Arc<dyn RequestEffects>,
        started: Duration,
    ) -> Result<Self, RequestError> {
        Self::open_with_clock(options, effects, started, Arc::new(clock::PlatformClock)).await
    }

    pub(super) async fn open_with_clock(
        options: RequestOptions,
        effects: Arc<dyn RequestEffects>,
        started: Duration,
        clock: Arc<dyn clock::ExecutionClock>,
    ) -> Result<Self, RequestError> {
        let policy = Arc::new(InferenceAttempts::with_clock(
            options.local,
            options.routed,
            options.max_buffered_bytes,
            options.model.clone(),
            clock.clone(),
        ));
        let mut request = Self {
            clock,
            policy: policy.clone(),
            effects,
            cancellation: RequestCancellation::new(policy),
            tasks: FuturesUnordered::new(),
            aborts: HashMap::new(),
            streams: HashMap::new(),
            models: HashMap::from([(0, options.model.clone())]),
            buffers: HashMap::new(),
            errors: HashMap::new(),
            output: VecDeque::new(),
            started,
            measurements: Measurements::default(),
            hedge_opened: None,
            finished: None,
            local: options.local,
        };
        if options.local {
            let effects = request.effects.clone();
            request
                .cancellation
                .register(0, Arc::new(move || effects.cancel(0)));
            let stream = work::open(
                request.effects.as_ref(),
                &request.cancellation,
                0,
                options.model,
            )
            .await?;
            request.streams.insert(0, stream);
            request.read(0);
        } else {
            if let Some(hedge) = &options.hedge {
                request.models.insert(1, hedge.model.clone());
            }
            request.observe(
                Observation::Start {
                    hedge_delay_ms: options.hedge.map(|hedge| hedge.delay_ms),
                    ceiling_ms: options.ceiling_ms,
                },
                0,
                None,
            );
        }
        Ok(request)
    }

    pub fn cancellation(&self) -> Arc<RequestCancellation> {
        self.cancellation.clone()
    }

    /// Retains winning-model and report-deduplication facts for the turn owner.
    pub fn attempts(&self) -> Arc<InferenceAttempts> {
        self.policy.clone()
    }

    /// Returns winning events in order, including the winner's pre-answer events.
    pub async fn next(&mut self) -> Result<Option<InferenceEvent>, RequestError> {
        let mut guard = CancelOnDrop(Some(self.cancellation.clone()));
        let result = self.next_inner().await;
        guard.0 = None;
        result
    }

    async fn next_inner(&mut self) -> Result<Option<InferenceEvent>, RequestError> {
        loop {
            if self.cancellation.is_cancelled() {
                self.policy.step(Observation::Cancel);
                self.stop_tasks();
                return Err(InferenceError::Cancelled.into());
            }
            // Ready provider work must not starve an already-due hedge or ceiling.
            self.perform(self.policy.drain_deadline(), 0, None);
            if let Some(event) = self.output.pop_front() {
                return Ok(Some(event));
            }
            if let Some(error) = &self.finished {
                let error = error.clone();
                return error.map_or(Ok(None), Err);
            }
            let policy = self.policy.clone();
            let local = self.local;
            let deadline = Box::pin(async move {
                if local || !policy.wait_for_deadline().await {
                    std::future::pending::<()>().await;
                }
            });
            let wake = select(
                select(self.tasks.next(), deadline),
                self.cancellation.wait(),
            )
            .await;
            match wake {
                Either::Right(_) => continue,
                Either::Left((Either::Right(_), _)) => {
                    self.perform(self.policy.drain_deadline(), 0, None);
                }
                Either::Left((Either::Left((Some(Some(work)), _)), _)) => {
                    self.perform(self.policy.drain_deadline(), 0, None);
                    if self.finished.is_none() && !self.cancellation.is_cancelled() {
                        self.completed(work);
                    }
                }
                Either::Left((Either::Left((Some(None), _)), _)) => {}
                Either::Left((Either::Left((None, _)), _)) => {
                    return Err(InferenceError::Interrupted.into());
                }
            }
        }
    }

    fn spawn(&mut self, id: u64, future: impl std::future::Future<Output = Work> + Send + 'static) {
        let (abort, registration) = AbortHandle::new_pair();
        let effects = self.effects.clone();
        let stream = self.streams.get(&id).cloned();
        let cancel_task = abort.clone();
        let policy = self.policy.clone();
        let model = self.models[&id].clone();
        self.cancellation.register(
            id,
            Arc::new(move || {
                cancel_task.abort();
                effects.cancel(id);
                if let Some(stream) = &stream {
                    stream.0.cancel();
                } else if id == 1 {
                    for action in policy.step(Observation::OpenFailed { id }) {
                        if matches!(action, Action::RecordOpenFailure { .. }) {
                            effects.record_failure(model.clone(), InferenceError::Cancelled.into());
                        }
                    }
                }
            }),
        );
        self.aborts.insert(id, abort);
        self.tasks
            .push(async move { Abortable::new(future, registration).await.ok() }.boxed());
    }

    fn read(&mut self, id: u64) {
        let stream = self.streams[&id].clone();
        self.spawn(id, async move {
            Work::Read {
                id,
                result: stream.0.next().await,
            }
        });
    }

    fn completed(&mut self, work: Work) {
        match work {
            Work::Opened { id, model, result } => match result {
                Ok(Some(stream)) => {
                    self.models.insert(id, model);
                    self.streams.insert(id, stream);
                    self.observe(Observation::Opened { id }, id, None);
                    if !self.buffers.contains_key(&id) {
                        self.streams.remove(&id);
                    }
                }
                Ok(None) => self.observe(Observation::NoReplacement { id }, id, None),
                Err(error) => {
                    self.errors.insert(id, error);
                    self.observe(Observation::OpenFailed { id }, id, None);
                }
            },
            Work::Read { id, result } => match result {
                Ok(Some(event)) => {
                    if self.local {
                        self.output.push_back(event);
                        self.read(id);
                    } else {
                        self.observe(
                            Observation::Event {
                                id,
                                kind: events::classify(&event),
                                bytes: events::buffered_bytes(&event),
                            },
                            id,
                            Some(event),
                        );
                        if self.streams.contains_key(&id) && self.finished.is_none() {
                            self.read(id);
                        }
                    }
                }
                ended => {
                    let error = match ended {
                        Err(error) => Some(error),
                        Ok(None) => self.buffers.get(&id).map(|events| events::unusable(events)),
                        _ => unreachable!(),
                    };
                    if let Some(error) = error {
                        self.errors.insert(id, error);
                    } else {
                        self.errors.remove(&id);
                    }
                    if self.local {
                        self.finished = Some(self.errors.remove(&id));
                        self.stop_tasks();
                    } else {
                        self.observe(Observation::Ended { id }, id, None);
                    }
                }
            },
        }
    }

    fn observe(&mut self, observation: Observation, source: u64, event: Option<InferenceEvent>) {
        self.perform(self.policy.step(observation), source, event);
    }
}

impl Drop for InferenceRequest {
    fn drop(&mut self) {
        self.effects.close();
        self.cancellation.cancel();
        self.policy.step(Observation::Cancel);
        self.stop_tasks();
    }
}
