use super::*;
use crate::inference::{
    request_driver::{RequestHost, bindings::platform::HostPlatform},
    routing::RoutingRequest,
};

/// Completes host context preparation with request-scoped platform capabilities.
#[derive(Default, uniffi::Object)]
pub struct TurnPrepareCallback(pub(super) Arc<Completion<PreparedTurnRequest>>);
#[uniffi::export]
impl TurnPrepareCallback {
    /// Returns false when cancellation or a previous completion already won.
    pub fn succeed(
        &self,
        provider_id: String,
        local: bool,
        routing: Option<RoutingRequest>,
        host: Box<dyn RequestHost>,
    ) -> bool {
        self.0.complete(Ok(PreparedTurnRequest {
            provider_id,
            local,
            routing,
            platform: HostPlatform::new(host.into()),
        }))
    }
    pub fn fail(&self, error: RequestError) {
        self.0.complete(Err(error));
    }
}

/// Acknowledges presentation work before the turn proceeds.
#[derive(Default, uniffi::Object)]
pub struct TurnNotifyCallback(pub(super) Arc<Completion<()>>);
#[uniffi::export]
impl TurnNotifyCallback {
    pub fn succeed(&self) -> bool {
        self.0.complete(Ok(()))
    }
}

/// Completes one tool execution; error results remain ordinary transcript results.
#[derive(Default, uniffi::Object)]
pub struct TurnToolCallback(pub(super) Arc<Completion<LocalToolResult>>);
#[uniffi::export]
impl TurnToolCallback {
    pub fn succeed(&self, result: LocalToolResult) -> bool {
        self.0.complete(Ok(result))
    }
}

/// Supplies the next round's tool definitions, preserving absent versus empty tools.
#[derive(Default, uniffi::Object)]
pub struct TurnToolsCallback(pub(super) Arc<Completion<Option<Vec<InferenceToolDefinition>>>>);
#[uniffi::export]
impl TurnToolsCallback {
    pub fn succeed(&self, tools: Option<Vec<InferenceToolDefinition>>) -> bool {
        self.0.complete(Ok(tools))
    }
}

/// Supplies lifecycle facts sampled at a turn-policy boundary.
#[derive(Default, uniffi::Object)]
pub struct TurnSignalsCallback(pub(super) Arc<Completion<TurnSignals>>);
#[uniffi::export]
impl TurnSignalsCallback {
    pub fn succeed(&self, signals: TurnSignals) -> bool {
        self.0.complete(Ok(signals))
    }
}
