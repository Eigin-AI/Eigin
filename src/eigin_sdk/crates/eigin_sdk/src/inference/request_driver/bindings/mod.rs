//! Synchronous host callbacks and single-use completions for foreign async runtimes.
use super::{
    InferenceRequest, RequestCandidate, RequestError, RequestPlatform, RequestReport,
    RoutedRequestEffects,
};
mod callbacks;
pub(crate) mod completion;
mod host;
mod operation;
pub(crate) mod platform;

pub use callbacks::*;
pub use host::RequestHost;
pub use operation::{InferenceRequestOperation, RequestSelection};

#[cfg(test)]
mod tests;
