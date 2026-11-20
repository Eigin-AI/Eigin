use super::super::race::{HEDGE, PRIMARY};
use super::super::{AttemptAction as A, AttemptObservation as O};
use super::fixtures::*;

#[test]
fn either_candidate_can_win_and_late_signals_are_inert() {
    for id in [PRIMARY, HEDGE] {
        let p = policy(false, true);
        assert_eq!(p.step(start(Some(0))), [A::Open { id: 0 }]);
        assert_eq!(p.drain_deadline(), [A::Open { id: 1 }]);
        for candidate in [PRIMARY, HEDGE] {
            assert_eq!(
                p.step(O::Opened { id: candidate }),
                [A::Forward { id: candidate }]
            );
            assert_eq!(p.step(event(candidate, false, 2)), [A::Buffer]);
        }
        assert_eq!(
            p.step(event(id, true, 10)),
            [A::Win { id }, A::Lose { id: 1 - id }, A::Deliver]
        );
        assert!(p.step(O::Ended { id: 1 - id }).is_empty());
        assert!(p.drain_deadline().is_empty());
        assert_eq!(p.step(event(id, false, u64::MAX)), [A::Deliver]);
        assert_eq!(
            p.step(O::Ended { id }),
            [A::Finish {
                error_source: id,
                timeout: false
            }]
        );
        assert!(p.step(event(id, true, 1)).is_empty());
    }
}
#[test]
fn empty_or_overflowing_stream_consults_recovery_before_output() {
    let p = policy(false, true);
    p.step(start(None));
    assert_eq!(p.step(event(0, false, 3)), [A::Overflow]);
    assert_eq!(
        p.step(O::Ended { id: 0 }),
        [A::Chase {
            failed: 0,
            replacement: 2,
            timeout: false
        }]
    );
    p.step(O::Opened { id: 2 });
    assert_eq!(
        p.step(O::Ended { id: 2 }),
        [A::Chase {
            failed: 2,
            replacement: 3,
            timeout: false
        }]
    );
    assert_eq!(
        p.step(O::NoReplacement { id: 3 }),
        [A::Finish {
            error_source: 3,
            timeout: false
        }]
    );
    p.exhausted();
    assert!(!p.should_report(true, false));
    assert!(p.should_report(false, false));
}
#[test]
fn hedge_can_settle_while_replacement_opens() {
    let p = policy(false, true);
    p.step(start(Some(0)));
    p.step(O::Ended { id: 0 });
    p.drain_deadline();
    p.step(O::Opened { id: 1 });
    assert_eq!(
        p.step(event(1, true, 1)),
        [A::Win { id: 1 }, A::Lose { id: 2 }, A::Deliver]
    );
    assert!(p.step(O::Opened { id: 2 }).is_empty());
    assert!(p.step(O::NoReplacement { id: 2 }).is_empty());
}

#[test]
fn hedge_open_failure_requests_its_sample_once() {
    let p = policy(false, true);
    p.step(start(Some(0)));
    p.drain_deadline();
    assert_eq!(
        p.step(O::OpenFailed { id: 1 }),
        [A::RecordOpenFailure { id: 1 }]
    );
    assert!(p.step(O::OpenFailed { id: 1 }).is_empty());
    assert!(p.step(event(0, true, 1)).contains(&A::Deliver));
}

#[test]
fn cancel_pending_hedge_without_reporting_attached_loss() {
    let p = policy(false, true);
    p.step(start(Some(0)));
    p.drain_deadline();
    assert_eq!(
        p.step(event(0, true, 1)),
        [A::Win { id: 0 }, A::CancelOpening { id: 1 }, A::Deliver]
    );
    assert_eq!(
        p.step(O::OpenFailed { id: 1 }),
        [A::RecordOpenFailure { id: 1 }]
    );
}

#[test]
fn two_failed_candidates_surface_primary_open_error_immediately() {
    let p = policy(false, true);
    p.step(start(Some(0)));
    p.drain_deadline();
    p.step(O::Opened { id: HEDGE });
    assert!(p.step(O::OpenFailed { id: PRIMARY }).is_empty());
    assert_eq!(
        p.step(O::Ended { id: HEDGE }),
        [A::Finish {
            error_source: PRIMARY,
            timeout: false
        }]
    );
}
