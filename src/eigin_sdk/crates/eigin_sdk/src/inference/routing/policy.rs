use std::time::Duration;

pub(super) const SESSION_IDLE_TIMEOUT: Duration = Duration::from_secs(3600);
pub(super) const ERROR_QUARANTINE: Duration = Duration::from_secs(300);
pub(super) const SLOWNESS_QUARANTINE: Duration = Duration::from_secs(120);
pub(super) const MAX_QUARANTINE: Duration = Duration::from_secs(3600);
pub(super) const QUARANTINE_BACKOFF_MULTIPLIER: f64 = 2.0;
pub(super) const SAMPLE_WINDOW: usize = 4;
pub(super) const SLOW_SAMPLES_TO_DEMOTE: usize = 3;

pub(super) const HEDGE_DELAY: Duration = Duration::from_secs(6);
pub(super) const SLOW_MODEL_HEDGE_DELAY: Duration = Duration::from_secs(3);
pub(super) const SLOW_SAMPLES_FOR_SHORT_HEDGE: usize = 2;

pub(super) const SLOW_FIRST_TOKEN: Duration = Duration::from_secs(10);
pub(super) const RECOVERED_FIRST_TOKEN: Duration = Duration::from_secs(8);
pub(super) const SLOW_THROUGHPUT: f64 = 5.0;
pub(super) const RECOVERED_THROUGHPUT: f64 = 6.0;
pub(super) const SPEED_MINIMUM_SAMPLES: u64 = 3;
pub(super) const FAILURE_MINIMUM_SAMPLES: u64 = 4;
pub(super) const PROBE_MINIMUM_SAMPLES: u64 = 1;
pub(super) const FAILURE_RATE_THRESHOLD: f64 = 0.5;

pub(super) const ASSUMED_OUTPUT_RESERVE: i64 = 256;
