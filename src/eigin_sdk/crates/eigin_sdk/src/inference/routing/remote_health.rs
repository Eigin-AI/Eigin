use super::{key, policy::*, types::*};
use crate::clock::WallTime;
use std::collections::HashMap;

#[derive(Default)]
struct Recency {
    observed: WallTime,
    ttft: Option<WallTime>,
    tps: Option<WallTime>,
}

#[derive(Default)]
struct Degradation {
    ttft: Option<MetricEvidence>,
    tps: Option<MetricEvidence>,
}

#[derive(Default)]
pub(super) struct RemoteHealth {
    snapshots: HashMap<String, HashMap<String, RoutingRemoteHealth>>,
    local: HashMap<(String, String), Recency>,
    degraded: HashMap<(String, String), Degradation>,
}

impl RemoteHealth {
    pub fn replace(&mut self, provider: String, observations: Vec<RoutingRemoteHealth>) {
        self.snapshots.insert(
            key(&provider),
            observations
                .into_iter()
                .map(|h| (key(&h.model), h))
                .collect(),
        );
    }

    pub fn reset(&mut self) {
        self.local.clear();
        self.degraded.clear();
    }

    pub fn success(&mut self, outcome: &RoutingOutcome, now: WallTime) {
        let r = self
            .local
            .entry((key(&outcome.provider_id), key(&outcome.model)))
            .or_default();
        r.observed = now;
        if outcome.first_token_seconds.is_some() {
            r.ttft = Some(now);
        }
        if outcome.tokens_per_second.is_some() {
            r.tps = Some(now);
        }
    }

    pub fn reason(
        &mut self,
        provider: &str,
        model: &str,
        now: WallTime,
    ) -> Option<RoutingDegradation> {
        let evidence_key = (key(provider), key(model));
        let Some(health) = self
            .snapshots
            .get(&key(provider))
            .and_then(|s| s.get(&key(model)))
        else {
            self.degraded.remove(&evidence_key);
            return None;
        };
        let ttft = newest(&health.ttft, SPEED_MINIMUM_SAMPLES, now);
        let tps = newest(&health.tps, SPEED_MINIMUM_SAMPLES, now);
        let failures = newest(&health.failures, FAILURE_MINIMUM_SAMPLES, now);
        let local = self.local.get(&evidence_key);
        let d = self.degraded.entry(evidence_key).or_default();
        d.ttft = update(
            d.ttft.take(),
            ttft,
            local.and_then(|r| r.ttft),
            |v| v > SLOW_FIRST_TOKEN.as_millis() as f64,
            |v| v < RECOVERED_FIRST_TOKEN.as_millis() as f64,
            now,
        );
        d.tps = update(
            d.tps.take(),
            tps,
            local.and_then(|r| r.tps),
            |v| v < SLOW_THROUGHPUT,
            |v| v > RECOVERED_THROUGHPUT,
            now,
        );
        if failures.is_some_and(|f| {
            f.value >= FAILURE_RATE_THRESHOLD && !local.is_some_and(|r| r.observed > f.observed_at)
        }) {
            return Some(RoutingDegradation::Errors);
        }
        if d.ttft.is_some() {
            return Some(RoutingDegradation::SlowFirstToken);
        }
        if d.tps.is_some() {
            return Some(RoutingDegradation::SlowThroughput);
        }
        None
    }
}

#[derive(Clone, Copy)]
struct MetricEvidence {
    value: f64,
    observed_at: WallTime,
    expires_at: WallTime,
}

fn newest(samples: &[RoutingHealthSample], minimum: u64, now: WallTime) -> Option<MetricEvidence> {
    // Equal timestamps retain the first sample.
    samples
        .iter()
        .filter(|s| {
            WallTime::from_unix_seconds(s.expires_at) > now
                && WallTime::from_unix_seconds(s.observed_at) <= now
                && s.count
                    >= if s.probe {
                        PROBE_MINIMUM_SAMPLES
                    } else {
                        minimum
                    }
        })
        .reduce(|a, b| if b.observed_at > a.observed_at { b } else { a })
        .map(|sample| MetricEvidence {
            value: sample.value,
            observed_at: WallTime::from_unix_seconds(sample.observed_at),
            expires_at: WallTime::from_unix_seconds(sample.expires_at),
        })
}

fn update(
    previous: Option<MetricEvidence>,
    evidence: Option<MetricEvidence>,
    local: Option<WallTime>,
    bad: impl Fn(f64) -> bool,
    recovered: impl Fn(f64) -> bool,
    now: WallTime,
) -> Option<MetricEvidence> {
    let mut current = previous.filter(|s| s.expires_at > now);
    if let Some(e) = evidence
        && current
            .as_ref()
            .is_none_or(|c| e.observed_at > c.observed_at)
    {
        if bad(e.value) {
            current = Some(e);
        } else if recovered(e.value) {
            current = None;
        }
    }
    if local.is_some_and(|l| current.as_ref().is_some_and(|c| l > c.observed_at)) {
        current = None;
    }
    current
}
