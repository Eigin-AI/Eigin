//! Host-provided inference with the same event lifecycle as cloud providers.
mod callbacks;
mod executor;
mod provider;
mod stream;
mod tools;

use super::{InferenceCompletionInput, InferenceError, InferenceEvent, InferenceToolCall};
pub use callbacks::*;
pub use executor::*;
pub use provider::*;
pub use stream::*;
pub use tools::*;

#[cfg(test)]
mod tests;
