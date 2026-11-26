//! Binding-safe turn operations and single-use host effect completions.
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, Ordering},
};
mod callbacks;
mod host;
mod operation;
#[cfg(test)]
mod tests;

use super::*;
use crate::{
    agent::{TurnFailure, TurnSignals},
    inference::{
        InferenceError, InferenceToolCall, InferenceToolDefinition,
        local::LocalToolResult,
        request_driver::{
            RequestError,
            bindings::completion::{Completion, Pending},
        },
    },
};
pub use callbacks::*;
use futures_util::{FutureExt, future::BoxFuture};
pub use host::TurnHost;
pub use operation::{ChatTurnOperation, InlineTurnOperation};
use std::{collections::HashMap, sync::atomic::AtomicU64};
