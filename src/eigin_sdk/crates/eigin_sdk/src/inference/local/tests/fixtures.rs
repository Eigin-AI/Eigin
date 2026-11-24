use super::super::*;
use std::{
    collections::VecDeque,
    sync::{
        Arc, Mutex,
        atomic::{AtomicUsize, Ordering},
    },
};

#[derive(Default)]
pub(super) struct Host {
    pub(super) open: Mutex<Option<Arc<LocalOpenCallback>>>,
    pub(super) read: Mutex<Option<Arc<LocalEventCallback>>>,
    pub(super) closes: AtomicUsize,
    pub(super) events: Mutex<VecDeque<InferenceEvent>>,
    pub(super) delay_open: bool,
    pub(super) delay_read: bool,
}
pub(super) struct Executor(pub(super) Arc<Host>);
impl LocalInferenceExecutor for Executor {
    fn start_request(
        &self,
        _: u64,
        input: InferenceCompletionInput,
        _: Option<Arc<LocalToolSession>>,
        c: Arc<LocalOpenCallback>,
    ) {
        assert_eq!(input.model, "gemma");
        if self.0.delay_open {
            *self.0.open.lock().unwrap() = Some(c);
        } else {
            c.succeed();
        }
    }
    fn read(&self, _: u64, c: Arc<LocalEventCallback>) {
        if self.0.delay_read {
            *self.0.read.lock().unwrap() = Some(c);
        } else {
            c.succeed(self.0.events.lock().unwrap().pop_front());
        }
    }
    fn close(&self, _: u64) {
        self.0.closes.fetch_add(1, Ordering::SeqCst);
    }
}
pub(super) fn stream(host: Arc<Host>) -> Arc<LocalInferenceStream> {
    LocalInferenceProvider::new(Box::new(Executor(host))).stream(
        InferenceCompletionInput {
            model: "gemma".into(),
            ..Default::default()
        },
        None,
    )
}
