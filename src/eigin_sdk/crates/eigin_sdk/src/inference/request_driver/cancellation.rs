use futures_channel::oneshot;
use futures_util::future::{BoxFuture, FutureExt, Shared};
use std::{
    collections::HashMap,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
};

type CancelEffect = Arc<dyn Fn() + Send + Sync>;

/// Stops a request, including pending preparation, opening, and event reads.
pub struct RequestCancellation {
    policy: Arc<crate::inference::InferenceAttempts>,
    cancelled: AtomicBool,
    sender: Mutex<Option<oneshot::Sender<()>>>,
    signal: Shared<BoxFuture<'static, ()>>,
    effects: Mutex<HashMap<u64, CancelEffect>>,
}

impl RequestCancellation {
    pub(super) fn new(policy: Arc<crate::inference::InferenceAttempts>) -> Arc<Self> {
        let (sender, receiver) = oneshot::channel();
        Arc::new(Self {
            policy,
            cancelled: AtomicBool::new(false),
            sender: Mutex::new(Some(sender)),
            signal: async move {
                let _ = receiver.await;
            }
            .boxed()
            .shared(),
            effects: Mutex::default(),
        })
    }

    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Release);
        self.policy
            .step(crate::inference::AttemptObservation::Cancel);
        self.sender.lock().unwrap().take();
        let effects = std::mem::take(&mut *self.effects.lock().unwrap());
        for effect in effects.into_values() {
            effect();
        }
    }

    pub(super) fn register(&self, id: u64, effect: CancelEffect) {
        let mut effects = self.effects.lock().unwrap();
        if self.is_cancelled() {
            drop(effects);
            effect();
        } else {
            effects.insert(id, effect);
        }
    }

    pub(super) fn remove(&self, id: u64) {
        self.effects.lock().unwrap().remove(&id);
    }

    pub(super) fn check(&self) -> Result<(), super::RequestError> {
        if self.is_cancelled() {
            Err(crate::inference::InferenceError::Cancelled.into())
        } else {
            Ok(())
        }
    }

    pub(super) fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::Acquire)
    }

    pub(super) fn wait(&self) -> Shared<BoxFuture<'static, ()>> {
        self.signal.clone()
    }
}

pub(super) struct CancelOnDrop(pub Option<Arc<RequestCancellation>>);
impl Drop for CancelOnDrop {
    fn drop(&mut self) {
        if let Some(cancel) = self.0.take() {
            cancel.cancel();
        }
    }
}
