//! Optional numeric payloads crossing generated event bindings.

use crate::inference::{InferenceEvent, InferencePerformance};

/// Emits operational events through the same bindings used by inference streams.
#[uniffi::export]
pub fn performance_events_fixture() -> Vec<InferenceEvent> {
    [(Some(125.5), Some(8.25)), (None, None), (Some(0.0), None)]
        .into_iter()
        .map(
            |(time_to_first_token_ms, tokens_per_second)| InferenceEvent::Performance {
                measurement: InferencePerformance {
                    time_to_first_token_ms,
                    tokens_per_second,
                },
            },
        )
        .collect()
}
