//! Rolling summaries with observation-based expiry.

use serde::Serialize;
use time::{OffsetDateTime, format_description::well_known::Rfc3339};

use super::{Observation, Outcome, Source};

/// Cached model-status response, served without upstream work.
#[derive(Clone, Debug, Serialize)]
pub struct StatusResponse {
    pub generated_at: String,
    pub models: Vec<ModelStatus>,
}

/// Independent traffic and synthetic evidence for a canonical model.
#[derive(Clone, Debug, Serialize)]
pub struct ModelStatus {
    pub id: String,
    pub traffic: Option<ObservationSummary>,
    pub probes: Option<ObservationSummary>,
}

/// Measurements and counts in a continuously rolling lookback.
#[derive(Clone, Debug, Serialize)]
pub struct ObservationSummary {
    pub sampled_at: String,
    pub expires_at: String,
    pub success_count: usize,
    pub failure_count: usize,
    pub ttft_sample_count: usize,
    pub throughput_sample_count: usize,
    pub ttft_sampled_at: Option<String>,
    pub tps_sampled_at: Option<String>,
    pub ttft_p50_ms: Option<f64>,
    pub tps_p50: Option<f64>,
}

impl StatusResponse {
    /// Aggregate fresh evidence, including unknown health for unsampled models.
    pub fn aggregate(
        models: impl IntoIterator<Item = String>,
        observations: &[Observation],
        now_ms: i64,
        lifetime_ms: i64,
    ) -> Self {
        assert!(lifetime_ms > 0);
        let cutoff = now_ms.saturating_sub(lifetime_ms);
        let mut models: Vec<_> = models
            .into_iter()
            .map(|id| {
                let summarize = |source, limit| {
                    let mut samples: Vec<_> = observations
                        .iter()
                        .filter(|sample| {
                            sample.model_id == id
                                && sample.source == source
                                && sample.observed_at_ms > cutoff
                                && sample.observed_at_ms <= now_ms
                        })
                        .collect();
                    samples.sort_by_key(|sample| std::cmp::Reverse(sample.observed_at_ms));
                    samples.truncate(limit);
                    summarize(&samples, cutoff, lifetime_ms)
                };
                ModelStatus {
                    traffic: summarize(Source::Traffic, 128),
                    probes: summarize(Source::Probe, 1),
                    id,
                }
            })
            .collect();
        models.sort_by(|a, b| a.id.cmp(&b.id));
        Self {
            generated_at: timestamp(now_ms),
            models,
        }
    }
}

fn summarize(
    samples: &[&Observation],
    cutoff: i64,
    lifetime_ms: i64,
) -> Option<ObservationSummary> {
    let latest = samples.first()?;
    let success_count = samples
        .iter()
        .filter(|sample| sample.outcome == Outcome::Success)
        .count();
    let measurements = |select: fn(&Observation) -> Option<f64>| {
        samples
            .iter()
            .filter(|sample| sample.outcome == Outcome::Success)
            .filter_map(|sample| select(sample))
            .filter(|value| value.is_finite() && *value >= 0.0)
            .collect::<Vec<_>>()
    };
    let ttft = measurements(|sample| sample.ttft_ms);
    let tps = measurements(|sample| sample.tps)
        .into_iter()
        .filter(|value| *value > 0.0)
        .collect::<Vec<_>>();
    let metric_timestamp = |select: fn(&Observation) -> Option<f64>, positive: bool| {
        samples
            .iter()
            .find(|sample| {
                sample.outcome == Outcome::Success
                    && select(sample).is_some_and(|value| {
                        value.is_finite() && if positive { value > 0.0 } else { value >= 0.0 }
                    })
            })
            .map(|sample| timestamp(sample.observed_at_ms))
    };
    Some(ObservationSummary {
        sampled_at: timestamp(latest.observed_at_ms),
        // Expire when the oldest contributing sample ages out, so a cached
        // aggregate cannot keep an expired failure alive through newer traffic.
        expires_at: timestamp(samples.last()?.observed_at_ms.saturating_add(lifetime_ms)),
        success_count,
        failure_count: samples.len() - success_count,
        ttft_sample_count: ttft.len(),
        throughput_sample_count: tps.len(),
        ttft_sampled_at: metric_timestamp(|sample| sample.ttft_ms, false),
        tps_sampled_at: metric_timestamp(|sample| sample.tps, true),
        ttft_p50_ms: median(ttft),
        tps_p50: median(tps),
    })
}

fn median(mut values: Vec<f64>) -> Option<f64> {
    if values.is_empty() {
        return None;
    }
    values.sort_by(f64::total_cmp);
    let middle = values.len() / 2;
    Some(if values.len() % 2 == 0 {
        values[middle - 1] / 2.0 + values[middle] / 2.0
    } else {
        values[middle]
    })
}

fn timestamp(ms: i64) -> String {
    OffsetDateTime::from_unix_timestamp_nanos(i128::from(ms) * 1_000_000)
        .expect("valid observation timestamp")
        .format(&Rfc3339)
        .expect("RFC3339 timestamp")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample(at: i64, outcome: Outcome, source: Source) -> Observation {
        Observation {
            model_id: "model".into(),
            source,
            observed_at_ms: at,
            outcome,
            ttft_ms: Some(200.0),
            tps: Some(10.0),
        }
    }

    fn aggregate(samples: &[Observation], now: i64) -> ModelStatus {
        StatusResponse::aggregate(["model".into()], samples, now, 900_000)
            .models
            .remove(0)
    }

    #[test]
    fn buffered_outcome_does_not_renew_metric_timestamps() {
        let mut buffered = sample(2000, Outcome::Success, Source::Traffic);
        buffered.ttft_ms = None;
        buffered.tps = None;
        let summary = aggregate(
            &[sample(1000, Outcome::Success, Source::Traffic), buffered],
            3000,
        )
        .traffic
        .unwrap();
        assert_eq!(summary.sampled_at, timestamp(2000));
        assert_eq!(summary.ttft_sampled_at, Some(timestamp(1000)));
        assert_eq!(summary.tps_sampled_at, Some(timestamp(1000)));
    }

    #[test]
    fn publishes_failures_without_waiting_for_full_window() {
        let samples = (1..=4)
            .map(|i| sample(i * 30_000, Outcome::Timeout, Source::Traffic))
            .collect::<Vec<_>>();
        let status = aggregate(&samples, 120_001).traffic.unwrap();
        assert_eq!(status.failure_count, 4);
        assert_eq!(status.success_count, 0);
        assert_eq!(status.ttft_p50_ms, None);
    }

    #[test]
    fn rolling_expiry_has_no_quarter_hour_reset() {
        let samples = [
            sample(60_000, Outcome::Timeout, Source::Traffic),
            sample(900_000, Outcome::Success, Source::Traffic),
        ];
        assert_eq!(
            aggregate(&samples, 959_999).traffic.unwrap().failure_count,
            1
        );
        let refreshed = aggregate(&samples, 960_000).traffic.unwrap();
        assert_eq!(refreshed.failure_count, 0);
        assert_eq!(refreshed.success_count, 1);
    }

    #[test]
    fn probe_remains_useful_for_fourteen_minutes() {
        let samples = [sample(1_000, Outcome::Success, Source::Probe)];
        assert!(aggregate(&samples, 841_000).probes.is_some());
        assert!(aggregate(&samples, 901_000).probes.is_none());
    }

    #[test]
    fn only_latest_probe_is_published_and_traffic_is_bounded() {
        let mut samples = (1..=200)
            .map(|i| sample(i, Outcome::Success, Source::Traffic))
            .collect::<Vec<_>>();
        samples.push(sample(100, Outcome::Timeout, Source::Probe));
        samples.push(sample(200, Outcome::Success, Source::Probe));
        let status = aggregate(&samples, 300);
        assert_eq!(status.traffic.unwrap().success_count, 128);
        assert_eq!(status.probes.unwrap().failure_count, 0);
    }

    #[test]
    fn missing_expired_and_future_samples_are_unknown() {
        let samples = [
            sample(1, Outcome::Success, Source::Traffic),
            sample(1_000_001, Outcome::Success, Source::Probe),
        ];
        let status = aggregate(&samples, 1_000_000);
        assert!(status.traffic.is_none());
        assert!(status.probes.is_none());
    }
}
