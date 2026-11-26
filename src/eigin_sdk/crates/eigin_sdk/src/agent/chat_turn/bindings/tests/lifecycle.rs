use super::super::*;
use crate::inference::request_driver::{
    RequestEventCallback, RequestHealthCallback, RequestHost, RequestInventoryCallback,
    RequestUnitCallback,
};
use futures::executor::block_on;
use std::sync::Weak;

#[derive(Default)]
struct State {
    operation: Mutex<Weak<ChatTurnOperation>>,
    preparing: Mutex<Option<Arc<TurnPrepareCallback>>>,
    notifying: Mutex<Option<Arc<TurnNotifyCallback>>>,
    cancellations: Mutex<Vec<u64>>,
    stop_during_notify: AtomicBool,
}
#[derive(Clone)]
struct Host(Arc<State>);
impl TurnHost for Host {
    fn present(&self, _: u64, _: TurnPresentation, completion: Arc<TurnNotifyCallback>) {
        completion.succeed();
    }
    fn prepare(
        &self,
        _: u64,
        _: TurnContext,
        _: Arc<InlineTurnOperation>,
        completion: Arc<TurnPrepareCallback>,
    ) {
        *self.0.preparing.lock().unwrap() = Some(completion);
    }
    fn notify(&self, _: u64, _: ChatTurnEvent, completion: Arc<TurnNotifyCallback>) {
        if self.0.stop_during_notify.load(Ordering::SeqCst) {
            self.0.operation.lock().unwrap().upgrade().unwrap().stop();
            *self.0.notifying.lock().unwrap() = Some(completion);
        } else {
            completion.succeed();
        }
    }
    fn execute(&self, _: u64, _: InferenceToolCall, _: Arc<TurnToolCallback>) {
        panic!("unexpected tool");
    }
    fn refresh_tools(&self, _: u64, _: Arc<TurnToolsCallback>) {
        panic!("unexpected refresh");
    }
    fn signals(&self, _: u64, _: TurnSignalBoundary, _: Arc<TurnSignalsCallback>) {
        panic!("unexpected signals");
    }
    fn classify_failure(&self, _: RequestError) -> TurnFailure {
        TurnFailure::Terminal
    }
    fn cancel_operation(&self, id: u64) {
        self.0.cancellations.lock().unwrap().push(id);
    }
}
impl RequestHost for Host {
    fn reported(
        &self,
        _: Option<crate::inference::request_driver::RequestReport>,
        _: crate::inference::routing::RoutingResult,
    ) {
    }
    fn validate(&self, _: u64, _: u64, _: String, _: Arc<RequestUnitCallback>) {
        panic!("late validation");
    }
    fn start_candidate(
        &self,
        _: u64,
        _: u64,
        _: String,
        _: Option<crate::model_catalog::CatalogReasoningEffort>,
        _: Arc<RequestUnitCallback>,
    ) {
        panic!("late dispatch");
    }
    fn read(&self, _: u64, _: u64, _: Arc<RequestEventCallback>) {
        panic!("late read");
    }
    fn refresh_catalog(&self, _: u64, _: String, _: Arc<RequestInventoryCallback>) {
        panic!("late catalog");
    }
    fn refresh_health(&self, _: u64, _: String, _: Arc<RequestHealthCallback>) {
        panic!("late health");
    }
    fn cancel_operation(&self, _: u64) {}
    fn cancel_candidate(&self, _: u64) {}
    fn wall_time(&self) -> f64 {
        0.0
    }
}
fn operation(state: Arc<State>) -> Arc<ChatTurnOperation> {
    let operation = ChatTurnOperation::new(
        ChatTurnInput {
            messages: vec![],
            tools: None,
            model: "model".into(),
            initial_instruction: None,
            allow_interruption_recovery: true,
            propagate_stream_cancellation: true,
        },
        crate::inference::routing::ModelRouter::new(),
        Box::new(Host(state.clone())),
    );
    *state.operation.lock().unwrap() = Arc::downgrade(&operation);
    operation
}

#[test]
fn reentrant_stop_closes_again_after_host_registration() {
    block_on(async {
        let state = Arc::new(State::default());
        state.stop_during_notify.store(true, Ordering::SeqCst);
        let operation = operation(state.clone());
        assert!(operation.run().await.unwrap().is_empty());
        assert!(!state.notifying.lock().unwrap().as_ref().unwrap().succeed());
        let cancellations = state.cancellations.lock().unwrap();
        assert!(cancellations.len() >= 2);
        assert!(cancellations.iter().all(|id| *id == cancellations[0]));
        assert!(state.preparing.lock().unwrap().is_none());
    });
}

#[test]
fn dropped_run_and_stop_reject_late_prepared_capabilities() {
    block_on(async {
        for stop in [false, true] {
            let state = Arc::new(State::default());
            let operation = operation(state.clone());
            let mut run = Box::pin(operation.run());
            assert!(futures::poll!(&mut run).is_pending());
            assert!(matches!(
                operation.run().await,
                Err(ChatTurnError::AlreadyStarted)
            ));
            let callback = state.preparing.lock().unwrap().clone().unwrap();
            if stop {
                assert!(operation.stop().is_empty());
                assert!(run.await.unwrap().is_empty());
            } else {
                drop(run);
            }
            assert!(!callback.succeed(
                "provider".into(),
                true,
                None,
                Box::new(Host(state.clone()))
            ));
            assert!(operation.checkpoint().is_empty());
        }
    });
}
