use super::{super::*, fixtures::*};
use futures::{FutureExt, executor::block_on};
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicUsize, Ordering},
};

struct Tools {
    pending: Arc<Mutex<Option<Arc<LocalToolCallback>>>>,
    cancels: Arc<AtomicUsize>,
}
impl LocalToolExecutor for Tools {
    fn execute(&self, _: InferenceToolCall, completion: Arc<LocalToolCallback>) {
        *self.pending.lock().unwrap() = Some(completion);
    }
    fn cancel(&self) {
        self.cancels.fetch_add(1, Ordering::SeqCst);
    }
}
#[test]
fn stream_cancellation_also_interrupts_inline_tools() {
    let pending = Arc::new(Mutex::new(None));
    let cancels = Arc::new(AtomicUsize::new(0));
    let tools = LocalToolSession::new(Box::new(Tools {
        pending: pending.clone(),
        cancels: cancels.clone(),
    }));
    let stream = LocalInferenceProvider::new(Box::new(Executor(Arc::new(Host::default())))).stream(
        InferenceCompletionInput {
            model: "gemma".into(),
            ..Default::default()
        },
        Some(tools.clone()),
    );
    block_on(stream.open()).unwrap();
    let mut call = Box::pin(tools.execute(InferenceToolCall::default()));
    assert!(call.as_mut().now_or_never().is_none());
    stream.cancel();
    assert!(matches!(block_on(call), Err(InferenceError::Cancelled)));
    pending
        .lock()
        .unwrap()
        .take()
        .unwrap()
        .succeed(LocalToolResult {
            tool_call_id: "late".into(),
            content: "late".into(),
            is_error: false,
        });
    assert!(matches!(
        block_on(tools.execute(InferenceToolCall::default())),
        Err(InferenceError::Cancelled)
    ));
    assert_eq!(cancels.load(Ordering::SeqCst), 1);
}
