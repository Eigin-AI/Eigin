use super::{RequestCandidate, RequestError};
use crate::{
    inference::routing::{RoutingInventory, RoutingRemoteHealth},
    model_catalog::CatalogReasoningEffort,
};
use futures_util::future::BoxFuture;
use std::sync::Arc;

/// Platform effects for a prepared request; routing decisions remain in the SDK.
/// Candidate IDs are request-scoped. Dropping pending work must cancel it.
pub trait RequestPlatform: Send + Sync {
    /// Delivers terminal timing even after cancellation, without admitting output.
    fn reported(
        &self,
        report: Option<crate::inference::request_driver::RequestReport>,
        result: crate::inference::routing::RoutingResult,
    ) {
        let _ = (report, result);
    }

    /// Checks the prepared prompt against a candidate without dispatching inference.
    fn validate(&self, id: u64, model: String) -> BoxFuture<'_, Result<(), RequestError>>;

    /// Opens a candidate using the SDK-selected reasoning effort.
    /// Supply classified errors to preserve provider-specific retry and health behavior.
    fn open(
        &self,
        id: u64,
        model: String,
        effort: Option<CatalogReasoningEffort>,
    ) -> BoxFuture<'_, Result<Arc<dyn RequestCandidate>, RequestError>>;

    /// Cancels candidate validation or dispatch. Repeated calls are harmless.
    fn cancel(&self, id: u64);

    /// Refreshes discovery/settings after a classified model-not-found failure.
    fn refresh_catalog(&self, provider_id: String) -> BoxFuture<'_, Option<RoutingInventory>>;

    /// Supplies remote observations before replacement selection. Empty values clear stale evidence.
    fn refresh_health(&self, provider_id: String) -> BoxFuture<'_, Vec<RoutingRemoteHealth>>;

    /// Wall-clock seconds since the Unix epoch, sampled on both sides of health refresh.
    fn wall_time(&self) -> f64 {
        match web_time::SystemTime::now().duration_since(web_time::UNIX_EPOCH) {
            Ok(duration) => duration.as_secs_f64(),
            Err(error) => -error.duration().as_secs_f64(),
        }
    }
}
