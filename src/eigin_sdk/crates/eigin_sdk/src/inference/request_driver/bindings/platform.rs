use super::{
    completion::{Completion, Pending},
    *,
};
use crate::{
    inference::{
        InferenceError, InferenceEvent,
        routing::{RoutingInventory, RoutingRemoteHealth},
    },
    model_catalog::CatalogReasoningEffort,
};
use futures_util::{FutureExt, future::BoxFuture};
use std::{
    collections::HashMap,
    sync::{
        Arc, Mutex,
        atomic::{AtomicU64, Ordering},
    },
};

static NEXT_OPERATION: AtomicU64 = AtomicU64::new(1);
struct PendingCall {
    candidate: Option<u64>,
    completion: Arc<dyn Pending>,
}
#[derive(Default)]
struct State {
    cancelled: bool,
    pending: HashMap<u64, PendingCall>,
}

#[derive(Clone)]
pub(crate) struct HostPlatform {
    host: Arc<dyn RequestHost>,
    state: Arc<Mutex<State>>,
}
impl HostPlatform {
    pub fn new(host: Arc<dyn RequestHost>) -> Arc<Self> {
        Arc::new(Self {
            host,
            state: Arc::default(),
        })
    }

    async fn call<T: Send + 'static>(
        &self,
        candidate: Option<u64>,
        completion: Arc<Completion<T>>,
        dispatch: impl FnOnce(u64),
    ) -> Result<T, RequestError> {
        let id = NEXT_OPERATION.fetch_add(1, Ordering::Relaxed);
        {
            let mut state = self.state.lock().unwrap();
            if state.cancelled {
                return Err(InferenceError::Cancelled.into());
            }
            state.pending.insert(
                id,
                PendingCall {
                    candidate,
                    completion: completion.clone(),
                },
            );
        }
        let _guard = CallGuard {
            platform: self.clone(),
            id,
            completion: completion.clone(),
        };
        dispatch(id);
        // Close again if cancellation ran before the host registered this operation.
        if !self.state.lock().unwrap().pending.contains_key(&id) {
            self.host.cancel_operation(id);
            if let Some(candidate) = candidate {
                self.host.cancel_candidate(candidate);
            }
        }
        completion.wait().await
    }

    pub fn cancel_all(&self) {
        let pending = {
            let mut state = self.state.lock().unwrap();
            state.cancelled = true;
            std::mem::take(&mut state.pending)
        };
        for (id, call) in pending {
            call.completion.cancel();
            self.host.cancel_operation(id);
            if let Some(candidate) = call.candidate {
                self.host.cancel_candidate(candidate);
            }
        }
    }
}

struct CallGuard {
    platform: HostPlatform,
    id: u64,
    completion: Arc<dyn Pending>,
}
impl Drop for CallGuard {
    fn drop(&mut self) {
        self.platform.state.lock().unwrap().pending.remove(&self.id);
        self.completion.cancel();
        self.platform.host.cancel_operation(self.id);
    }
}

struct HostCandidate {
    platform: HostPlatform,
    id: u64,
}
impl RequestCandidate for HostCandidate {
    fn next(&self) -> BoxFuture<'_, Result<Option<InferenceEvent>, RequestError>> {
        async move {
            let callback = Arc::new(RequestEventCallback::default());
            self.platform
                .call(Some(self.id), callback.0.clone(), |operation| {
                    self.platform.host.read(operation, self.id, callback);
                })
                .await
        }
        .boxed()
    }
    fn cancel(&self) {
        self.platform.cancel(self.id);
    }
}

impl RequestPlatform for HostPlatform {
    fn reported(
        &self,
        report: Option<crate::inference::request_driver::RequestReport>,
        result: crate::inference::routing::RoutingResult,
    ) {
        self.host.reported(report, result);
    }

    fn validate(&self, id: u64, model: String) -> BoxFuture<'_, Result<(), RequestError>> {
        async move {
            let callback = Arc::new(RequestUnitCallback::default());
            self.call(Some(id), callback.0.clone(), |operation| {
                self.host.validate(operation, id, model, callback);
            })
            .await
        }
        .boxed()
    }

    fn open(
        &self,
        id: u64,
        model: String,
        effort: Option<CatalogReasoningEffort>,
    ) -> BoxFuture<'_, Result<Arc<dyn RequestCandidate>, RequestError>> {
        async move {
            let callback = Arc::new(RequestUnitCallback::default());
            let result = self
                .call(Some(id), callback.0.clone(), |operation| {
                    self.host
                        .start_candidate(operation, id, model, effort, callback);
                })
                .await;
            if let Err(error) = result {
                self.host.cancel_candidate(id);
                return Err(error);
            }
            Ok(Arc::new(HostCandidate {
                platform: self.clone(),
                id,
            }) as Arc<dyn RequestCandidate>)
        }
        .boxed()
    }

    fn cancel(&self, id: u64) {
        let pending = {
            let mut state = self.state.lock().unwrap();
            let ids: Vec<_> = state
                .pending
                .iter()
                .filter(|(_, pending)| pending.candidate == Some(id))
                .map(|(id, _)| *id)
                .collect();
            ids.into_iter()
                .map(|id| (id, state.pending.remove(&id).unwrap()))
                .collect::<Vec<_>>()
        };
        for (operation, call) in pending {
            call.completion.cancel();
            self.host.cancel_operation(operation);
        }
        self.host.cancel_candidate(id);
    }

    fn refresh_catalog(&self, provider_id: String) -> BoxFuture<'_, Option<RoutingInventory>> {
        async move {
            let callback = Arc::new(RequestInventoryCallback::default());
            self.call(None, callback.0.clone(), |operation| {
                self.host.refresh_catalog(operation, provider_id, callback);
            })
            .await
            .unwrap_or(None)
        }
        .boxed()
    }

    fn refresh_health(&self, provider_id: String) -> BoxFuture<'_, Vec<RoutingRemoteHealth>> {
        async move {
            let callback = Arc::new(RequestHealthCallback::default());
            self.call(None, callback.0.clone(), |operation| {
                self.host.refresh_health(operation, provider_id, callback);
            })
            .await
            .unwrap_or_default()
        }
        .boxed()
    }
    fn wall_time(&self) -> f64 {
        self.host.wall_time()
    }
}
