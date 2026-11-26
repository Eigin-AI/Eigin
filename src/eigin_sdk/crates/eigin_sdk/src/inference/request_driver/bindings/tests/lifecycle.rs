use super::super::*;
use crate::{
    inference::{InferenceError, InferenceEvent, routing::ModelRouter},
    model_catalog::CatalogReasoningEffort,
};
use futures::{FutureExt, executor::block_on};
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, Ordering},
};

#[derive(Default)]
struct HostState {
    pending_open: AtomicBool,
    opened: Mutex<Option<Arc<RequestUnitCallback>>>,
    read: Mutex<Option<Arc<RequestEventCallback>>>,
    operations: Mutex<Vec<u64>>,
    cancelled: Mutex<Vec<u64>>,
    during_start: Mutex<Option<Box<dyn Fn() + Send + Sync>>>,
}
struct Host(Arc<HostState>);
impl RequestHost for Host {
    fn reported(
        &self,
        _: Option<crate::inference::request_driver::RequestReport>,
        _: crate::inference::routing::RoutingResult,
    ) {
    }
    fn validate(&self, _: u64, _: u64, _: String, completion: Arc<RequestUnitCallback>) {
        completion.succeed();
    }
    fn start_candidate(
        &self,
        _: u64,
        _: u64,
        _: String,
        _: Option<CatalogReasoningEffort>,
        completion: Arc<RequestUnitCallback>,
    ) {
        if let Some(hook) = self.0.during_start.lock().unwrap().as_ref() {
            hook();
        }
        *self.0.opened.lock().unwrap() = Some(completion.clone());
        if !self.0.pending_open.load(Ordering::SeqCst) {
            completion.succeed();
        }
    }
    fn read(&self, _: u64, _: u64, completion: Arc<RequestEventCallback>) {
        *self.0.read.lock().unwrap() = Some(completion);
    }
    fn refresh_catalog(&self, _: u64, _: String, completion: Arc<RequestInventoryCallback>) {
        completion.succeed(None);
    }
    fn refresh_health(&self, _: u64, _: String, completion: Arc<RequestHealthCallback>) {
        completion.succeed(vec![]);
    }
    fn cancel_operation(&self, id: u64) {
        self.0.operations.lock().unwrap().push(id);
    }
    fn cancel_candidate(&self, id: u64) {
        self.0.cancelled.lock().unwrap().push(id);
    }
    fn wall_time(&self) -> f64 {
        0.0
    }
}
fn operation(local: bool) -> (Arc<InferenceRequestOperation>, Arc<HostState>) {
    let host = Arc::new(HostState::default());
    let operation = InferenceRequestOperation::new(
        ModelRouter::new(),
        Box::new(Host(host.clone())),
        "provider".into(),
        "model".into(),
        local,
        None,
    );
    (operation, host)
}
fn cancelled<T>(result: Result<T, RequestError>) -> bool {
    matches!(
        result,
        Err(RequestError::Inference(InferenceError::Cancelled))
    )
}

#[test]
fn local_open_is_cancellable_and_late_success_is_rejected() {
    block_on(async {
        let (operation, host) = operation(true);
        host.pending_open.store(true, Ordering::SeqCst);
        let mut open = Box::pin(operation.open());
        assert!(futures::poll!(&mut open).is_pending());
        let callback = host.opened.lock().unwrap().clone().unwrap();
        operation.cancel();
        assert!(cancelled(open.await));
        assert!(!callback.succeed());
        assert!(host.cancelled.lock().unwrap().contains(&0));
        assert!(cancelled(operation.next().await));
    });
}

#[test]
fn pending_read_rejects_overlap_and_cancellation_preserves_attribution() {
    block_on(async {
        let (operation, host) = operation(false);
        operation.open().await.unwrap();
        let mut next = Box::pin(operation.next());
        assert!(futures::poll!(&mut next).is_pending());
        assert!(matches!(
            operation.next().await,
            Err(RequestError::Inference(InferenceError::Busy))
        ));
        let callback = host.read.lock().unwrap().clone().unwrap();
        let event = InferenceEvent::ContentDelta {
            text: "answer".into(),
        };
        assert!(callback.succeed(Some(event.clone())));
        assert!(!callback.succeed(None));
        assert_eq!(next.await.unwrap(), Some(event.clone()));
        operation.observe_output(event).unwrap();
        operation.cancel();
        assert_eq!(operation.selection().unwrap().model, "model");
        let report = operation
            .report(crate::inference::routing::RoutingResult::Cancelled)
            .unwrap()
            .unwrap();
        assert!(report.first_token_seconds.is_some());
        assert!(host.cancelled.lock().unwrap().contains(&0));
    });
}

#[test]
fn dropped_open_and_read_futures_cancel_host_work() {
    block_on(async {
        let (opening, host) = operation(true);
        host.pending_open.store(true, Ordering::SeqCst);
        assert!(opening.open().now_or_never().is_none());
        assert!(!host.opened.lock().unwrap().as_ref().unwrap().succeed());
        assert!(host.cancelled.lock().unwrap().contains(&0));
        let (reading, host) = operation(false);
        reading.open().await.unwrap();
        assert!(reading.next().now_or_never().is_none());
        assert!(!host.read.lock().unwrap().as_ref().unwrap().succeed(None));
        assert!(host.cancelled.lock().unwrap().contains(&0));
        assert!(cancelled(reading.next().await));
    });
}

#[test]
fn cancellation_during_host_registration_closes_again_after_dispatch() {
    block_on(async {
        let (operation, host) = operation(true);
        let weak = Arc::downgrade(&operation);
        *host.during_start.lock().unwrap() =
            Some(Box::new(move || weak.upgrade().unwrap().cancel()));
        assert!(cancelled(operation.open().await));
        assert!(!host.opened.lock().unwrap().as_ref().unwrap().succeed());
        assert!(host.cancelled.lock().unwrap().len() >= 2);
    });
}
