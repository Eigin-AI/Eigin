use crate::inference::{InferenceEvent, InferencePerformance};
use web_time::Instant;

/// Useful-output timing shared by every provider adapter.
#[derive(Default)]
pub(crate) struct Performance {
    started: Option<Instant>,
    received_at: Option<f64>,
    first: Option<f64>,
    last: Option<f64>,
    useful_tokens: Option<u64>,
}

impl Performance {
    /// Call once before HTTP dispatch, using a fresh instance for each request.
    pub fn start(&mut self) {
        self.started = Some(Instant::now());
    }

    /// Capture arrival time before parsing each transport chunk, not each SSE event.
    pub fn received_chunk(&mut self) {
        self.received_at = self.started.map(|started| started.elapsed().as_secs_f64());
    }

    /// Mark nonempty text/tool output while parsing the current chunk; exclude thinking.
    pub fn useful_output(&mut self) {
        if let Some(elapsed) = self.received_at {
            self.first.get_or_insert(elapsed);
            self.last = Some(elapsed);
        }
    }

    /// Replace usage with cumulative provider counts, including the final usage event.
    /// Missing counts or reasoning exceeding the total leave throughput unavailable.
    pub fn tokens(&mut self, total: Option<u64>, reasoning: Option<u64>) {
        self.useful_tokens = total
            .zip(reasoning)
            .and_then(|(total, reasoning)| total.checked_sub(reasoning));
    }

    /// Emit after final usage and before a successful finish.
    /// Throughput requires both output times, a positive interval, and at least four tokens.
    pub fn event(&self) -> InferenceEvent {
        let tokens_per_second = self
            .first
            .zip(self.last)
            .zip(self.useful_tokens)
            .filter(|((first, last), tokens)| *tokens >= 4 && last > first)
            .map(|((first, last), tokens)| tokens as f64 / (last - first));
        InferenceEvent::Performance {
            measurement: InferencePerformance {
                time_to_first_token_ms: self.first.map(|first| first * 1000.0),
                tokens_per_second,
            },
        }
    }
}
