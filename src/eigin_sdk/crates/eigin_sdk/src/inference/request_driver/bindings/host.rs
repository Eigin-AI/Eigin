use super::*;
use crate::model_catalog::CatalogReasoningEffort;
use std::sync::Arc;

/// Per-request platform capabilities. Methods schedule host work and complete once.
/// Operation IDs identify callback work; candidate IDs identify native stream lifetimes.
#[uniffi::export(callback_interface)]
pub trait RequestHost: Send + Sync {
    /// Delivers terminal timing even after cancellation, without admitting output.
    fn reported(
        &self,
        report: Option<crate::inference::request_driver::RequestReport>,
        result: crate::inference::routing::RoutingResult,
    );

    fn validate(
        &self,
        operation_id: u64,
        candidate_id: u64,
        model: String,
        completion: Arc<RequestUnitCallback>,
    );
    fn start_candidate(
        &self,
        operation_id: u64,
        candidate_id: u64,
        model: String,
        effort: Option<CatalogReasoningEffort>,
        completion: Arc<RequestUnitCallback>,
    );
    fn read(&self, operation_id: u64, candidate_id: u64, completion: Arc<RequestEventCallback>);
    fn refresh_catalog(
        &self,
        operation_id: u64,
        provider_id: String,
        completion: Arc<RequestInventoryCallback>,
    );
    fn refresh_health(
        &self,
        operation_id: u64,
        provider_id: String,
        completion: Arc<RequestHealthCallback>,
    );
    fn cancel_operation(&self, operation_id: u64);
    fn cancel_candidate(&self, candidate_id: u64);
    fn wall_time(&self) -> f64;
}
