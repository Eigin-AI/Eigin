use super::{AttemptAction, AttemptObservation, ReplacementWork, race::Race};
use crate::clock;
use futures_util::future::select;
use std::sync::Mutex;

#[derive(Default)]
struct Routing {
    switches: u8,
    refreshed: bool,
    reported: bool,
    retry: Option<String>,
    winner: Option<String>,
}

/// Transient policy for one request, independent of agent turn recovery.
#[derive(uniffi::Object)]
pub struct InferenceAttempts {
    local: bool,
    routed: bool,
    limit: u64,
    starting: String,
    race: Mutex<Race>,
    routing: Mutex<Routing>,
}

#[uniffi::export]
impl InferenceAttempts {
    #[uniffi::constructor]
    pub fn new(local: bool, routed: bool, max_buffered_bytes: u64, starting_model: String) -> Self {
        Self {
            local,
            routed: routed && !local,
            limit: max_buffered_bytes,
            starting: starting_model,
            race: Mutex::default(),
            routing: Mutex::default(),
        }
    }
    /// Local dispatch errors propagate from open rather than stream iteration.
    pub fn opens_directly(&self) -> bool {
        self.local
    }
    /// Advances one serialized observation. Apply its actions before submitting the next observation.
    pub fn step(&self, observation: AttemptObservation) -> Vec<AttemptAction> {
        if self.local {
            return vec![];
        }
        let observation = match observation {
            AttemptObservation::Start { ceiling_ms, .. } if !self.routed => {
                AttemptObservation::Start {
                    ceiling_ms,
                    hedge_delay_ms: None,
                }
            }
            other => other,
        };
        self.race
            .lock()
            .unwrap()
            .step(observation, self.limit, clock::now())
    }
    /// Waits for SDK timer work without changing the race. False after settlement or cancellation.
    pub async fn wait_for_deadline(&self) -> bool {
        loop {
            let (deadline, change) = {
                let mut race = self.race.lock().unwrap();
                if self.local || race.finished_waiting() {
                    return false;
                }
                let deadline = race.next_deadline();
                if deadline.is_some_and(|at| at <= clock::now()) {
                    return true;
                }
                (deadline, race.deadline_change())
            };
            if let Some(at) = deadline {
                select(change, std::pin::pin!(clock::sleep_until(at))).await;
            } else {
                let _ = change.await;
            }
        }
    }
    /// Applies the earliest still-due deadline on the host's serialized observation lane.
    pub fn drain_deadline(&self) -> Vec<AttemptAction> {
        self.race.lock().unwrap().drain(clock::now())
    }
    /// Describes one chase. Failed replacement opens retain the original failure attribution (#442).
    pub fn replacement_work(
        &self,
        failed_model: String,
        missing_model: bool,
        cancelled: bool,
    ) -> ReplacementWork {
        let mut r = self.routing.lock().unwrap();
        let refresh = !cancelled && self.routed && missing_model && !r.refreshed;
        r.refreshed |= refresh;
        ReplacementWork {
            record_model: (!cancelled).then_some(failed_model),
            refresh,
            rank: !cancelled && self.routed && r.switches < 2,
        }
    }
    /// Spends a switch on dispatch, even when the replacement fails to open.
    pub fn claim_switch(&self, chase: u64, from: String, to: String) -> bool {
        let mut r = self.routing.lock().unwrap();
        let mut race = self.race.lock().unwrap();
        if race.can_replace(chase) && self.routed && from != to && r.switches < 2 {
            race.arm_dispatch(clock::now());
            r.switches += 1;
            true
        } else {
            false
        }
    }
    /// Retains retry selection separately from the model that produced useful output.
    pub fn replacement_opened(&self, model: String) {
        self.routing.lock().unwrap().retry = Some(model);
    }
    /// Associates the winning candidate with its host model name.
    pub fn selected(&self, model: String) {
        self.routing.lock().unwrap().winner.get_or_insert(model);
    }
    /// The last pre-output failure has already been reported.
    pub fn exhausted(&self) {
        self.routing.lock().unwrap().reported = true;
    }
    pub fn winning_model(&self) -> String {
        self.routing
            .lock()
            .unwrap()
            .winner
            .as_ref()
            .unwrap_or(&self.starting)
            .clone()
    }
    pub fn retry_won(&self) -> bool {
        let r = self.routing.lock().unwrap();
        r.retry.as_ref() == Some(r.winner.as_ref().unwrap_or(&self.starting))
    }
    /// Deduplicates an exhausted failure while retaining cancellations and successes.
    pub fn should_report(&self, failed: bool, observed_content: bool) -> bool {
        !(failed && !observed_content && self.routing.lock().unwrap().reported)
    }
}

#[cfg(feature = "binding-tests")]
#[uniffi::export]
impl InferenceAttempts {
    /// Test fixture barrier for cancelling a wait that registered through the host binding.
    pub fn binding_wait_registered(&self) -> bool {
        self.race.lock().unwrap().wait_registered()
    }
}
