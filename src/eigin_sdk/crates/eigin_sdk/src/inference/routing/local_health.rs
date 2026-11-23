use super::{key, policy::*, types::*};
use crate::clock::WallTime;
use std::collections::HashMap;
use std::time::Duration;

#[derive(Default)]
struct Entry {
    until: Option<WallTime>,
    quarantines: u32,
    retired: bool,
    samples: Vec<(bool, bool)>,
}

#[derive(Default)]
pub(super) struct LocalHealth {
    entries: HashMap<String, Entry>,
    activity: Option<WallTime>,
}

impl LocalHealth {
    pub fn open_session(&mut self, now: WallTime) -> bool {
        let Some(last) = self.activity else {
            self.activity = Some(now);
            return false;
        };
        if now.seconds_since(last) <= SESSION_IDLE_TIMEOUT.as_secs_f64() {
            return false;
        }
        self.entries.clear();
        self.activity = Some(now);
        true
    }

    pub fn activity(&mut self, now: WallTime) {
        self.activity = Some(now);
    }

    pub fn healthy(&self, model: &str, now: WallTime) -> bool {
        self.entries
            .get(&key(model))
            .is_none_or(|e| !e.retired && e.until.is_none_or(|t| now >= t))
    }

    pub fn retired(&self, model: &str) -> bool {
        self.entries.get(&key(model)).is_some_and(|e| e.retired)
    }

    pub fn slow_samples(&self, model: &str) -> usize {
        self.entries
            .get(&key(model))
            .map_or(0, |e| e.samples.iter().filter(|s| s.0).count())
    }

    pub fn quarantine(&mut self, model: &str, now: WallTime, base: Duration) {
        let e = self.entries.entry(key(model)).or_default();
        e.quarantines = e.quarantines.saturating_add(1);
        let multiplier = QUARANTINE_BACKOFF_MULTIPLIER.powf(f64::from(e.quarantines - 1));
        let seconds = (base.as_secs_f64() * multiplier).min(MAX_QUARANTINE.as_secs_f64());
        e.until = Some(now.after(Duration::from_secs_f64(seconds)));
        e.samples.clear();
        super::diagnostics::event(
            "model quarantined",
            model,
            &[
                ("expires_at", e.until.unwrap().unix_seconds()),
                ("consecutive_quarantines", f64::from(e.quarantines)),
            ],
        );
        self.activity(now);
    }

    pub fn failure(&mut self, model: &str, failure: RoutingFailure, now: WallTime) {
        match failure {
            RoutingFailure::ModelNotFound => {
                self.entries.entry(key(model)).or_default().retired = true;
                super::diagnostics::event("model retired", model, &[]);
                self.activity(now);
            }
            RoutingFailure::ProviderOverloaded | RoutingFailure::TimedOut => {
                self.quarantine(model, now, ERROR_QUARANTINE)
            }
            _ => {}
        }
    }

    pub fn sample(&mut self, model: &str, ttft: bool, tps: bool, now: WallTime) -> bool {
        let e = self.entries.entry(key(model)).or_default();
        e.samples.push((ttft, tps));
        if e.samples.len() > SAMPLE_WINDOW {
            e.samples.remove(0);
        }
        let degraded = e.samples.iter().filter(|s| s.0).count() >= SLOW_SAMPLES_TO_DEMOTE
            || e.samples.iter().filter(|s| s.1).count() >= SLOW_SAMPLES_TO_DEMOTE;
        self.activity(now);
        degraded
    }

    pub fn success(&mut self, model: &str, now: WallTime) {
        if let Some(e) = self.entries.get_mut(&key(model)) {
            e.quarantines = 0;
        }
        self.activity(now);
    }
}
