//! Content-free, rolling observations of upstream model performance.

pub mod measurement;
pub mod probes;
pub mod service;
pub mod store;
mod summary;

pub use summary::{ModelStatus, ObservationSummary, StatusResponse};

use serde::{Deserialize, Serialize};

/// Origin of a model performance observation.
#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Source {
    Traffic,
    Probe,
}

/// Completed upstream outcome. Client cancellations are never observations.
#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Outcome {
    Success,
    Timeout,
    Overloaded,
    UpstreamFailure,
}

/// Operational measurements only; no content or user identifiers.
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct Observation {
    pub model_id: String,
    pub source: Source,
    /// Unix milliseconds at completion.
    pub observed_at_ms: i64,
    pub outcome: Outcome,
    pub ttft_ms: Option<f64>,
    pub tps: Option<f64>,
}
