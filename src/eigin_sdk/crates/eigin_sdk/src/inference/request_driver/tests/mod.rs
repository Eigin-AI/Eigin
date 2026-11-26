mod cancellation;
mod flow;
mod hedging;
mod routing;
mod useful_output;

use super::*;
use crate::inference::{InferenceError, InferenceEvent, InferenceFinishReason, InferenceToolCall};
use futures::{FutureExt, executor::block_on, future::BoxFuture};
use std::{
    collections::{HashMap, VecDeque},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
};

mod fixtures;
pub(super) use fixtures::*;
mod reporting;
