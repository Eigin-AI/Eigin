use super::{AttemptAction, AttemptObservation};
use futures_channel::oneshot;
use futures_util::future::{FutureExt, Shared};
use std::time::Duration;

pub(super) const PRIMARY: u64 = 0;
pub(super) const HEDGE: u64 = 1;

#[derive(Default)]
pub(super) struct Race {
    started: bool,
    done: bool,
    primary: u64,
    next: u64,
    hedge_at: Option<Duration>,
    ceiling_at: Option<Duration>,
    ceiling: Duration,
    change: Option<(oneshot::Sender<()>, Shared<oneshot::Receiver<()>>)>,
    hedge_opening: bool,
    hedge_open: bool,
    hedge_dead: bool,
    primary_dead: bool,
    chasing: bool,
    expired_once: bool,
    winner: Option<u64>,
    bytes: [u64; 2],
}

impl Race {
    pub(super) fn step(
        &mut self,
        observation: AttemptObservation,
        limit: u64,
        now: Duration,
    ) -> Vec<AttemptAction> {
        let before = (self.next_deadline(), self.finished_waiting());
        let actions = self.transition(observation, limit, now);
        if self.finished_waiting() {
            self.hedge_at = None;
            self.ceiling_at = None;
        }
        if before != (self.next_deadline(), self.finished_waiting()) {
            self.changed();
        }
        actions
    }
    pub(super) fn can_replace(&self, chase: u64) -> bool {
        !self.finished_waiting() && self.chasing && self.primary == chase
    }
    pub(super) fn deadline_change(&mut self) -> Shared<oneshot::Receiver<()>> {
        self.change
            .get_or_insert_with(|| {
                let (tx, rx) = oneshot::channel();
                (tx, rx.shared())
            })
            .1
            .clone()
    }
    #[cfg(feature = "binding-tests")]
    pub(super) fn wait_registered(&self) -> bool {
        self.change.is_some()
    }

    pub(super) fn next_deadline(&self) -> Option<Duration> {
        self.hedge_at.into_iter().chain(self.ceiling_at).min()
    }
    pub(super) fn finished_waiting(&self) -> bool {
        self.done || self.winner.is_some()
    }
    // Dropping the sender wakes waiters registered against the previous deadline.
    fn changed(&mut self) {
        self.change.take();
    }
    pub(super) fn drain(&mut self, now: Duration) -> Vec<AttemptAction> {
        let Some(due) = self.next_deadline() else {
            return vec![];
        };
        if self.finished_waiting() || due > now {
            return vec![];
        }
        self.changed();
        // On a tie, give the host the hedge open first; drain one expiry per actor turn.
        if self.hedge_at == Some(due) {
            self.hedge_at = None;
            self.hedge_opening = true;
            return vec![AttemptAction::Open { id: HEDGE }];
        }
        self.ceiling_at = None;
        if self.expired_once {
            return self.finish(self.primary, true);
        }
        self.expired_once = true;
        self.ceiling_at = Some(now + self.ceiling);
        if self.live_hedge() || self.chasing {
            vec![]
        } else {
            self.chase(true)
        }
    }
    pub(super) fn arm_dispatch(&mut self, now: Duration) {
        self.ceiling_at = Some(now + self.ceiling);
        self.changed();
    }
    fn live_hedge(&self) -> bool {
        self.hedge_open && !self.hedge_dead
    }
    fn chase(&mut self, timeout: bool) -> Vec<AttemptAction> {
        let failed = self.primary;
        self.next += 1;
        self.primary = self.next;
        self.chasing = true;
        self.bytes[0] = 0;
        vec![AttemptAction::Chase {
            failed,
            replacement: self.primary,
            timeout,
        }]
    }
    fn finish(&mut self, error_source: u64, timeout: bool) -> Vec<AttemptAction> {
        self.done = true;
        vec![AttemptAction::Finish {
            error_source,
            timeout,
        }]
    }
    fn transition(
        &mut self,
        input: AttemptObservation,
        limit: u64,
        now: Duration,
    ) -> Vec<AttemptAction> {
        use AttemptAction as A;
        use AttemptObservation as O;
        // Even a cancelled opening hedge currently records its failure (#446).
        if matches!(input, O::OpenFailed { id: HEDGE }) && self.hedge_opening {
            self.hedge_opening = false;
            return vec![A::RecordOpenFailure { id: HEDGE }];
        }
        if self.done {
            return vec![];
        }
        match input {
            O::Start {
                hedge_delay_ms,
                ceiling_ms,
            } if !self.started => {
                self.started = true;
                self.next = HEDGE;
                self.ceiling = Duration::from_millis(ceiling_ms.into());
                self.ceiling_at = Some(now + self.ceiling);
                self.hedge_at = hedge_delay_ms.map(|ms| now + Duration::from_millis(ms.into()));
                vec![A::Open { id: PRIMARY }]
            }
            O::Cancel => {
                self.done = true;
                vec![]
            }
            _ if !self.started => vec![],
            O::Opened { id } if self.winner.is_none() => {
                if id == HEDGE {
                    self.hedge_opening = false;
                    self.hedge_open = true;
                } else if id != self.primary {
                    return vec![];
                } else if self.chasing {
                    self.chasing = false;
                }
                vec![A::Forward { id }]
            }
            O::NoReplacement { id }
                if self.winner.is_none() && self.chasing && self.primary == id =>
            {
                self.finish(id, false)
            }
            O::Event { id, kind, bytes } if self.active(id) => {
                if self.winner.is_some() {
                    return vec![A::Deliver];
                }
                if !kind.wins() {
                    let total = &mut self.bytes[usize::from(id == HEDGE)];
                    if bytes.max(1) > limit - *total {
                        return vec![A::Overflow];
                    }
                    *total += bytes.max(1);
                    return vec![A::Buffer];
                }
                self.winner = Some(id);
                let mut work = vec![A::Win { id }];
                if id != HEDGE && self.hedge_opening {
                    work.push(A::CancelOpening { id: HEDGE });
                }
                if id == HEDGE || self.hedge_open {
                    work.push(A::Lose {
                        id: if id == HEDGE { self.primary } else { HEDGE },
                    });
                }
                work.push(A::Deliver);
                work
            }
            O::OpenFailed { id } | O::Ended { id } if self.active(id) => {
                if self.winner.is_some() {
                    return self.finish(id, false);
                }
                if id == HEDGE {
                    self.hedge_dead = true;
                    if self.primary_dead {
                        return self.finish(self.primary, false);
                    }
                } else if !self.live_hedge() {
                    return self.chase(false);
                } else {
                    self.primary_dead = true;
                }
                vec![]
            }
            _ => vec![],
        }
    }
    fn active(&self, id: u64) -> bool {
        self.winner.is_none_or(|w| w == id)
            && (id == HEDGE && self.live_hedge()
                || id == self.primary && !self.chasing && !self.primary_dead)
    }
}
