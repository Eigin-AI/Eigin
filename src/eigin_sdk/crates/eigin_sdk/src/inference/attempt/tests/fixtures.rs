use super::super::{AttemptEvent, AttemptObservation as O, InferenceAttempts};

pub(super) fn policy(local: bool, routed: bool) -> InferenceAttempts {
    InferenceAttempts::new(local, routed, 2, "A".into())
}
pub(super) fn start(hedge_delay_ms: Option<u32>) -> O {
    O::Start {
        hedge_delay_ms,
        ceiling_ms: 10000,
    }
}
pub(super) fn event(id: u64, useful: bool, bytes: u64) -> O {
    O::Event {
        id,
        kind: AttemptEvent::Content { nonempty: useful },
        bytes,
    }
}
