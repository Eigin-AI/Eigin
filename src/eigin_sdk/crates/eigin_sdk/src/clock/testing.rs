use super::execution::{ClockSleep, ExecutionClock};
use futures::channel::oneshot;
use std::{
    sync::{Arc, Mutex},
    time::Duration,
};

/// Injected time source advanced explicitly by request behavior tests.
#[derive(Default)]
pub(crate) struct ManualClock {
    state: Arc<Mutex<State>>,
}

#[derive(Default)]
struct State {
    now: Duration,
    waits: Vec<(Duration, oneshot::Sender<()>)>,
}

impl ExecutionClock for ManualClock {
    fn now(&self) -> Duration {
        self.state.lock().unwrap().now
    }

    fn sleep_until(&self, deadline: Duration) -> ClockSleep {
        let state = self.state.clone();
        Box::pin(async move {
            let wait = {
                let mut state = state.lock().unwrap();
                if deadline <= state.now {
                    return;
                }
                let (send, wait) = oneshot::channel();
                state.waits.push((deadline, send));
                wait
            };
            let _ = wait.await;
        })
    }
}

impl ManualClock {
    pub fn advance(&self, duration: Duration) {
        let ready = {
            let mut state = self.state.lock().unwrap();
            state.now += duration;
            let mut ready = vec![];
            let mut pending = vec![];
            for (deadline, send) in std::mem::take(&mut state.waits) {
                if deadline <= state.now {
                    ready.push(send);
                } else {
                    pending.push((deadline, send));
                }
            }
            state.waits = pending;
            ready
        };
        for send in ready {
            let _ = send.send(());
        }
    }
}
