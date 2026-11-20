use super::super::race::Race;
use super::super::race::{HEDGE, PRIMARY};
use super::super::{AttemptAction as A, AttemptObservation as O};
use super::fixtures::*;
use futures_util::FutureExt;
use std::time::Duration;

#[test]
fn timeout_chases_once_and_rearms_for_replacement() {
    let p = policy(false, true);
    p.step(O::Start {
        hedge_delay_ms: None,
        ceiling_ms: 0,
    });
    assert_eq!(
        p.drain_deadline(),
        [A::Chase {
            failed: 0,
            replacement: 2,
            timeout: true
        }]
    );
    assert!(p.step(event(0, true, 1)).is_empty());
    assert!(p.claim_switch(2, "A".into(), "B".into()));
    assert_eq!(p.step(O::Opened { id: 2 }), [A::Forward { id: 2 }]);
    assert_eq!(
        p.drain_deadline(),
        [A::Finish {
            error_source: 2,
            timeout: true
        }]
    );
    assert_eq!(p.winning_model(), "A"); // #444: the silent replacement never won.
}
#[test]
fn simultaneous_deadlines_open_hedge_then_spend_ceiling_once() {
    let mut race = Race::default();
    let t = Duration::ZERO;
    race.step(
        O::Start {
            hedge_delay_ms: Some(0),
            ceiling_ms: 0,
        },
        1,
        t,
    );
    assert_eq!(race.drain(t), [A::Open { id: HEDGE }]);
    assert_eq!(
        race.drain(t),
        [A::Chase {
            failed: PRIMARY,
            replacement: 2,
            timeout: true
        }]
    );
    assert!(matches!(
        race.drain(t).as_slice(),
        [A::Finish { timeout: true, .. }]
    ));
}
#[test]
fn pending_wait_observes_deadline_change_and_cancellation() {
    use std::{
        future::Future,
        sync::{Arc, mpsc},
        task::{Context, Wake, Waker},
    };
    struct Notify(mpsc::Sender<()>);
    impl Wake for Notify {
        fn wake(self: Arc<Self>) {
            self.0.send(()).unwrap();
        }
    }
    let p = policy(false, true);
    let (tx, rx) = mpsc::channel();
    let waker = Waker::from(Arc::new(Notify(tx)));
    let mut cx = Context::from_waker(&waker);
    let mut waiting = Box::pin(p.wait_for_deadline());
    assert!(waiting.as_mut().poll(&mut cx).is_pending());
    p.step(start(Some(0)));
    rx.recv_timeout(Duration::from_secs(1)).unwrap();
    assert_eq!(waiting.now_or_never(), Some(true));
    p.drain_deadline();
    let mut waiting = Box::pin(p.wait_for_deadline());
    assert!(waiting.as_mut().poll(&mut cx).is_pending());
    p.step(O::Cancel);
    rx.recv_timeout(Duration::from_secs(1)).unwrap();
    assert_eq!(waiting.now_or_never(), Some(false));
}

#[test]
fn replacement_rearms_a_pending_ceiling_from_dispatch() {
    let mut race = Race::default();
    let t = Duration::from_secs(1);
    race.step(start(None), 2, t);
    race.step(O::OpenFailed { id: PRIMARY }, 2, t);
    race.arm_dispatch(t + Duration::from_secs(3));
    race.step(O::Opened { id: 2 }, 2, t + Duration::from_secs(4));
    assert!(race.drain(t + Duration::from_secs(10)).is_empty());
    assert_eq!(
        race.drain(t + Duration::from_secs(13)),
        [A::Chase {
            failed: 2,
            replacement: 3,
            timeout: true
        }]
    );
}

#[test]
fn event_winning_between_wake_and_drain_suppresses_dispatch() {
    let p = policy(false, true);
    p.step(start(Some(0)));
    assert_eq!(p.wait_for_deadline().now_or_never(), Some(true));
    p.step(event(0, true, 1));
    assert!(p.drain_deadline().is_empty());
    assert_eq!(p.wait_for_deadline().now_or_never(), Some(false));
}

#[test]
fn timeout_chase_with_stalled_headers_expires() {
    let mut race = Race::default();
    let t = Duration::ZERO;
    race.step(start(None), 1, t);
    race.drain(Duration::from_secs(10));
    race.arm_dispatch(Duration::from_secs(11));
    assert_eq!(
        race.drain(Duration::from_secs(21)),
        [A::Finish {
            error_source: 2,
            timeout: true
        }]
    );
}
