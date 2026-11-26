use crate::inference::routing::ModelRouter;
use futures_channel::oneshot;
use futures_util::future::BoxFuture;
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, Ordering},
};
mod cancellation;
mod flow;

use super::*;
use crate::{
    agent::{TurnFailure, TurnSignals},
    inference::{
        InferenceError, InferenceEvent, InferenceFinishReason, InferenceToolCall,
        InferenceToolDefinition,
        local::LocalToolResult,
        request_driver::{RequestCandidate, RequestError, RequestPlatform},
        routing::{RoutingInventory, RoutingRemoteHealth},
    },
    model_catalog::CatalogReasoningEffort,
};
use futures::{FutureExt, executor::block_on};
use std::{
    collections::{HashMap, VecDeque},
    sync::atomic::AtomicUsize,
};

mod fixtures;
use fixtures::*;
mod headless;
