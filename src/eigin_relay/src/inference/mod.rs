//! Inference proxy: OpenAI-compatible endpoints backed by a European upstream provider.
//!
//! Routes:
//! - GET  /v1/models           — curated model catalog
//! - POST /v1/chat/completions — streaming and non-streaming, with credit metering

pub mod catalog;
pub mod estimate;
pub mod handler;
pub mod rates;
pub mod upstream;
pub mod usage;
