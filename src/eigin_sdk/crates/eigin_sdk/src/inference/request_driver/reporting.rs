use super::*;
use crate::inference::{InferencePerformance, routing::RoutingResult};

/// Accepted-output evidence attributed to the winning model of one request.
#[derive(Clone, Debug, uniffi::Record)]
pub struct RequestReport {
    pub model: String,
    pub first_token_seconds: Option<f64>,
    pub tokens_per_second: Option<f64>,
    pub result: RoutingResult,
}

#[derive(Default)]
pub(super) struct Measurements {
    first_content: Option<Duration>,
    performance: Option<InferencePerformance>,
}

impl InferenceRequest {
    /// Samples output only after the turn has accepted it into its current round.
    pub fn observe_output(&mut self, event: &InferenceEvent) {
        let now = self.clock.now();
        match event {
            InferenceEvent::ContentDelta { text }
                if !text.is_empty() && self.measurements.first_content.is_none() =>
            {
                self.measurements.first_content = Some(now);
            }
            InferenceEvent::Performance { measurement } => {
                self.measurements.performance = Some(measurement.clone());
            }
            _ => {}
        }
    }

    /// Records the turn's classified outcome, preserving exhausted-failure deduplication.
    pub fn report(&self, result: RoutingResult) -> Option<RequestReport> {
        if !self.policy.should_report(
            matches!(result, RoutingResult::Failed { .. }),
            self.measurements.first_content.is_some(),
        ) {
            self.effects.reported(None, result);
            return None;
        }
        let measured = matches!(result, RoutingResult::Succeeded)
            .then_some(self.measurements.performance.as_ref())
            .flatten();
        let report = RequestReport {
            model: self.policy.winning_model(),
            first_token_seconds: measured
                .and_then(|measurement| measurement.time_to_first_token_ms)
                .map(|milliseconds| milliseconds / 1000.0)
                .or_else(|| {
                    self.measurements
                        .first_content
                        .map(|at| at.saturating_sub(self.started).as_secs_f64())
                }),
            tokens_per_second: measured.and_then(|measurement| measurement.tokens_per_second),
            result,
        };
        self.effects
            .reported(Some(report.clone()), report.result.clone());
        self.effects.record_outcome(report.clone());
        Some(report)
    }
}
