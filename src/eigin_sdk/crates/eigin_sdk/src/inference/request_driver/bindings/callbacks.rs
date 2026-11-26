use super::{RequestError, completion::Completion};
use crate::inference::{
    InferenceEvent,
    routing::{RoutingInventory, RoutingRemoteHealth},
};
use std::sync::Arc;

/// Single-use completion for candidate validation or opening.
#[derive(Default, uniffi::Object)]
pub struct RequestUnitCallback(pub(super) Arc<Completion<()>>);
#[uniffi::export]
impl RequestUnitCallback {
    /// Returns false if the operation has already completed or been cancelled.
    pub fn succeed(&self) -> bool {
        self.0.complete(Ok(()))
    }
    pub fn fail(&self, error: RequestError) {
        self.0.complete(Err(error));
    }
}

/// Single-use completion for an ordered candidate event or end-of-stream.
#[derive(Default, uniffi::Object)]
pub struct RequestEventCallback(pub(super) Arc<Completion<Option<InferenceEvent>>>);
#[uniffi::export]
impl RequestEventCallback {
    pub fn succeed(&self, event: Option<InferenceEvent>) -> bool {
        self.0.complete(Ok(event))
    }
    pub fn fail(&self, error: RequestError) {
        self.0.complete(Err(error));
    }
}

/// Single-use completion for refreshed provider discovery and settings.
#[derive(Default, uniffi::Object)]
pub struct RequestInventoryCallback(pub(super) Arc<Completion<Option<RoutingInventory>>>);
#[uniffi::export]
impl RequestInventoryCallback {
    pub fn succeed(&self, inventory: Option<RoutingInventory>) -> bool {
        self.0.complete(Ok(inventory))
    }
}

/// Single-use completion for refreshed remote health observations.
#[derive(Default, uniffi::Object)]
pub struct RequestHealthCallback(pub(super) Arc<Completion<Vec<RoutingRemoteHealth>>>);
#[uniffi::export]
impl RequestHealthCallback {
    pub fn succeed(&self, observations: Vec<RoutingRemoteHealth>) -> bool {
        self.0.complete(Ok(observations))
    }
}
