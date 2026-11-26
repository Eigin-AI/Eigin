use super::*;
use crate::agent::{AgentRound, AgentTurn, AgentTurnOutput, TurnOutputEntry, TurnSignals};
use crate::inference::{request_driver::RequestCancellation, routing::ModelRouter};
use futures_channel::oneshot;
use futures_util::future::{BoxFuture, Either, FutureExt, Shared, select};
use std::{
    future::Future,
    sync::{Arc, Mutex, atomic::AtomicBool},
};

pub(super) struct State {
    pub(super) output: AgentTurnOutput,
    pub(super) round: Option<Arc<AgentRound>>,
    pub(super) request: Option<Arc<RequestCancellation>>,
    pub(super) model: String,
    pub(super) stopped: bool,
    pub(super) cancelled: bool,
    pub(super) closed: bool,
}

/// One operation owns all round/output state; stop and snapshots never await host callbacks.
pub struct ChatTurn {
    pub(super) input: ChatTurnInput,
    pub(super) router: Arc<ModelRouter>,
    pub(super) host: Arc<dyn ChatTurnHost>,
    pub(super) progression: AgentTurn,
    pub(super) state: Mutex<State>,
    pub(super) started: AtomicBool,
    pub(super) sender: Mutex<Option<oneshot::Sender<()>>>,
    pub(super) signal: Shared<BoxFuture<'static, ()>>,
}

impl ChatTurn {
    /// Creates an unstarted turn with a shared router and one initial context submission.
    pub fn new(
        input: ChatTurnInput,
        router: Arc<ModelRouter>,
        host: Arc<dyn ChatTurnHost>,
    ) -> Arc<Self> {
        let (sender, receiver) = oneshot::channel();
        Arc::new(Self {
            state: Mutex::new(State {
                output: AgentTurnOutput::new(),
                round: None,
                request: None,
                model: input.model.clone(),
                stopped: false,
                cancelled: false,
                closed: false,
            }),
            input,
            router,
            host,
            progression: AgentTurn::new(),
            started: AtomicBool::new(false),
            sender: Mutex::new(Some(sender)),
            signal: async move {
                let _ = receiver.await;
            }
            .boxed()
            .shared(),
        })
    }

    /// Stops admission of output and returns the immediate persistence checkpoint.
    pub fn stop(&self) -> Vec<TurnOutputEntry> {
        let (request, checkpoint) = {
            let mut state = self.state.lock().unwrap();
            state.stopped = true;
            (state.request.clone(), state.output.checkpoint())
        };
        self.sender.lock().unwrap().take();
        if let Some(request) = request {
            request.cancel();
        }
        checkpoint
    }

    /// Cancels suspended context, presentation, inference, or tool work.
    pub fn cancel(&self) {
        let request = {
            let mut state = self.state.lock().unwrap();
            state.cancelled = true;
            state.request.clone()
        };
        self.sender.lock().unwrap().take();
        if let Some(request) = request {
            request.cancel();
        }
    }

    /// Returns a stable-provenance snapshot without changing output admission.
    pub fn checkpoint(&self) -> Vec<TurnOutputEntry> {
        self.state.lock().unwrap().output.checkpoint()
    }

    /// Returns the committed display prefix, excluding unsettled final prose.
    pub fn retained_output(&self) -> Vec<TurnOutputEntry> {
        self.state.lock().unwrap().output.retained_output()
    }

    /// Number of reserved inference requests, including the active request.
    pub fn rounds_executed(&self) -> u32 {
        self.progression.rounds_executed()
    }

    /// Current round prose for presentation; output admission remains SDK-owned.
    pub fn partial_content(&self) -> String {
        self.state
            .lock()
            .unwrap()
            .round
            .as_ref()
            .map_or_else(String::new, |round| round.partial_content())
    }

    /// Current request winner, retained across automatic continuation.
    pub fn active_model(&self) -> String {
        self.state.lock().unwrap().model.clone()
    }

    pub(super) fn active_state(&self) -> Result<std::sync::MutexGuard<'_, State>, ChatTurnError> {
        let state = self.state.lock().unwrap();
        if state.stopped {
            Err(ChatTurnError::Stopped)
        } else if state.cancelled || state.closed {
            Err(ChatTurnError::Cancelled)
        } else {
            Ok(state)
        }
    }

    pub(super) fn ensure_active(&self) -> Result<(), ChatTurnError> {
        self.active_state().map(drop)
    }

    pub(super) async fn wait<T>(&self, work: impl Future<Output = T>) -> Result<T, ChatTurnError> {
        self.ensure_active()?;
        match select(Box::pin(work), self.signal.clone()).await {
            Either::Left((value, _)) => {
                self.ensure_active()?;
                Ok(value)
            }
            Either::Right(_) => {
                self.ensure_active()?;
                Err(ChatTurnError::Cancelled)
            }
        }
    }

    pub(super) async fn notify(&self, event: ChatTurnEvent) -> Result<(), ChatTurnError> {
        self.wait(self.host.notify(event)).await
    }

    pub(super) async fn present(&self, work: TurnPresentation) -> Result<(), ChatTurnError> {
        self.wait(self.host.present(work)).await
    }

    pub(super) async fn signals(
        &self,
        boundary: TurnSignalBoundary,
    ) -> Result<TurnSignals, ChatTurnError> {
        self.wait(self.host.signals(boundary)).await
    }

    pub(super) fn close(&self) {
        let request = {
            let mut state = self.state.lock().unwrap();
            state.closed = true;
            state.round = None;
            state.request.take()
        };
        self.sender.lock().unwrap().take();
        if let Some(request) = request {
            request.cancel();
        }
    }
}
