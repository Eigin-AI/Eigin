use super::*;
use crate::inference::{
    InferenceError, InferenceEvent,
    routing::{ModelRouter, RoutingRequest, RoutingResult},
};
use futures_util::future::{AbortHandle, AbortRegistration, Abortable};
use std::sync::{Arc, Mutex};

#[derive(Default)]
struct State {
    opened: bool,
    busy: bool,
    cancelled: bool,
    request: Option<InferenceRequest>,
    cancellation: Option<Arc<super::super::RequestCancellation>>,
    abort: Option<AbortHandle>,
}

/// Binding-safe request operation. Cancellation remains available while opening or reading.
#[derive(uniffi::Object)]
pub struct InferenceRequestOperation {
    model: String,
    effects: Arc<RoutedRequestEffects>,
    platform: Arc<platform::HostPlatform>,
    state: Mutex<State>,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct RequestSelection {
    pub model: String,
    pub retry_won: bool,
}

#[uniffi::export]
impl InferenceRequestOperation {
    /// Creates an independent request using a shared router and request-scoped host capabilities.
    #[uniffi::constructor]
    pub fn new(
        router: Arc<ModelRouter>,
        host: Box<dyn RequestHost>,
        provider_id: String,
        model: String,
        local: bool,
        routing: Option<RoutingRequest>,
    ) -> Arc<Self> {
        let platform = platform::HostPlatform::new(host.into());
        let effects =
            RoutedRequestEffects::new(router, platform.clone(), provider_id, local, routing);
        Arc::new(Self {
            model,
            effects,
            platform,
            state: Mutex::default(),
        })
    }

    /// Opens once; local runtime preparation completes before this returns.
    pub async fn open(&self) -> Result<(), RequestError> {
        let (mut lease, registration) = self.begin(true, false)?;
        let result =
            Abortable::new(self.effects.clone().start(self.model.clone()), registration).await;
        let result = match result {
            Ok(Ok(request)) => {
                lease.request = Some(request);
                Ok(())
            }
            Ok(Err(error)) => Err(error),
            Err(_) => Err(InferenceError::Cancelled.into()),
        };
        if lease.finish() {
            return Err(InferenceError::Cancelled.into());
        }
        result
    }

    /// Reads winning events. Overlapping reads fail with Busy rather than cancelling the first.
    pub async fn next(&self) -> Result<Option<InferenceEvent>, RequestError> {
        let (mut lease, registration) = self.begin(false, false)?;
        let result = Abortable::new(lease.request.as_mut().unwrap().next(), registration)
            .await
            .unwrap_or_else(|_| Err(InferenceError::Cancelled.into()));
        if lease.finish() {
            return Err(InferenceError::Cancelled.into());
        }
        result
    }

    /// Samples only events accepted by the turn owner.
    pub fn observe_output(&self, event: InferenceEvent) -> Result<(), RequestError> {
        let (mut lease, _) = self.begin(false, true)?;
        lease.request.as_mut().unwrap().observe_output(&event);
        lease.finish();
        Ok(())
    }

    /// Reports accepted output even after cancellation has stopped generation.
    pub fn report(&self, result: RoutingResult) -> Result<Option<RequestReport>, RequestError> {
        let (lease, _) = self.begin(false, true)?;
        let result = lease.request.as_ref().unwrap().report(result);
        lease.finish();
        Ok(result)
    }

    /// Returns the actual winner and whether it was a replacement.
    pub fn selection(&self) -> Result<RequestSelection, RequestError> {
        let (lease, _) = self.begin(false, true)?;
        let policy = lease.request.as_ref().unwrap().attempts();
        let result = RequestSelection {
            model: policy.winning_model(),
            retry_won: policy.retry_won(),
        };
        lease.finish();
        Ok(result)
    }

    /// Cancels host effects and native candidates, waking a pending open or read.
    pub fn cancel(&self) {
        let (abort, cancellation) = {
            let mut state = self.state.lock().unwrap();
            state.cancelled = true;
            (state.abort.clone(), state.cancellation.clone())
        };
        if let Some(abort) = abort {
            abort.abort();
        }
        if let Some(cancellation) = cancellation {
            cancellation.cancel();
        }
        self.platform.cancel_all();
    }
}

impl InferenceRequestOperation {
    fn begin(
        &self,
        opening: bool,
        allow_cancelled: bool,
    ) -> Result<(Lease<'_>, AbortRegistration), RequestError> {
        let mut state = self.state.lock().unwrap();
        if state.cancelled && !allow_cancelled {
            return Err(InferenceError::Cancelled.into());
        }
        if state.busy || (opening && state.opened) || (!opening && state.request.is_none()) {
            return Err(InferenceError::Busy.into());
        }
        state.opened = true;
        state.busy = true;
        let (abort, registration) = AbortHandle::new_pair();
        state.abort = Some(abort);
        let request = state.request.take();
        Ok((
            Lease {
                operation: self,
                request,
                finished: false,
            },
            registration,
        ))
    }
}

impl Drop for InferenceRequestOperation {
    fn drop(&mut self) {
        self.cancel();
    }
}

struct Lease<'a> {
    operation: &'a InferenceRequestOperation,
    request: Option<InferenceRequest>,
    finished: bool,
}
impl Lease<'_> {
    fn restore(&mut self) -> bool {
        let cancellation = self.request.as_ref().map(InferenceRequest::cancellation);
        let cancelled = {
            let mut state = self.operation.state.lock().unwrap();
            state.cancellation = cancellation.clone();
            state.request = self.request.take();
            state.busy = false;
            state.abort = None;
            state.cancelled
        };
        if cancelled && let Some(cancellation) = cancellation {
            cancellation.cancel();
        }
        cancelled
    }
    fn finish(mut self) -> bool {
        self.finished = true;
        self.restore()
    }
}
impl Drop for Lease<'_> {
    fn drop(&mut self) {
        if !self.finished {
            self.operation.cancel();
            self.restore();
        }
    }
}
