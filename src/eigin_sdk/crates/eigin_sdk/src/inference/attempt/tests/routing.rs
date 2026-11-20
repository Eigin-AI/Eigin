use super::super::{AttemptAction as A, AttemptObservation as O};
use super::fixtures::*;

#[test]
fn budgets_belong_to_one_routed_request() {
    for (local, routed) in [(true, true), (false, false), (false, true)] {
        let p = policy(local, routed);
        assert_eq!(p.opens_directly(), local);
        let eligible = routed && !local;
        assert!(!p.replacement_work("A".into(), false, false).refresh);
        assert_eq!(
            p.replacement_work("A".into(), true, false).refresh,
            eligible
        );
        assert!(!p.replacement_work("A".into(), true, false).refresh);
        p.step(start(None));
        p.step(O::Ended { id: 0 });
        assert!(!p.claim_switch(2, "A".into(), "A".into()));
        assert_eq!(p.claim_switch(2, "A".into(), "B".into()), eligible);
        assert_eq!(p.claim_switch(2, "B".into(), "C".into()), eligible);
        assert!(!p.replacement_work("A".into(), false, false).rank);
    }
}
#[test]
fn same_model_hedge_preserves_existing_persistence_attribution() {
    let p = policy(false, true);
    p.replacement_opened("B".into());
    assert!(!p.retry_won());
    p.selected("B".into());
    assert!(p.retry_won()); // #445
}

#[test]
fn local_bypasses_race_and_unrouted_cloud_keeps_its_ceiling() {
    let local = policy(true, true);
    assert!(local.step(start(Some(0))).is_empty());
    let cloud = policy(false, false);
    assert_eq!(cloud.step(start(Some(0))), [A::Open { id: 0 }]);
    let work = cloud.replacement_work("A".into(), true, false);
    assert_eq!(work.record_model.as_deref(), Some("A"));
    assert!(!work.refresh && !work.rank);
    let cancelled = policy(false, true).replacement_work("A".into(), true, true);
    assert!(cancelled.record_model.is_none() && !cancelled.refresh && !cancelled.rank);
}

#[test]
fn ranking_result_after_hedge_win_cannot_authorize_dispatch() {
    let p = policy(false, true);
    p.step(start(Some(0)));
    p.step(O::Ended { id: 0 });
    assert!(p.replacement_work("A".into(), false, false).rank);
    p.drain_deadline();
    p.step(O::Opened { id: 1 });
    p.step(event(1, true, 2));
    assert!(!p.claim_switch(2, "A".into(), "B".into()));
}
