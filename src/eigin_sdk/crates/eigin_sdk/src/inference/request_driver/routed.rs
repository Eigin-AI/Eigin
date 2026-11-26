use super::{
    InferenceRequest, RequestCandidate, RequestEffects, RequestError, RequestHedge, RequestOptions,
    RequestPlatform,
};
use crate::{
    inference::routing::{
        ModelRouter, RoutingInventory, RoutingOutcome, RoutingRequest, RoutingResult,
    },
    model_catalog::CatalogReasoningEffort,
};
use futures_util::{FutureExt, future::BoxFuture};
use std::sync::{Arc, Mutex};

/// Composes request execution with the shared SDK router and platform effects.
/// Construct one adapter per prepared request; retain the router across turns.
pub struct RoutedRequestEffects {
    router: Arc<ModelRouter>,
    platform: Arc<dyn RequestPlatform>,
    provider_id: String,
    local: bool,
    initial: Option<RoutingRequest>,
    inventory: Mutex<Option<RoutingInventory>>,
    on_close: Mutex<Option<Arc<dyn Fn() + Send + Sync>>>,
}

impl RoutedRequestEffects {
    /// Binds one request's provider and inventory; local execution ignores cloud routing inputs.
    pub fn new(
        router: Arc<ModelRouter>,
        platform: Arc<dyn RequestPlatform>,
        provider_id: String,
        local: bool,
        request: Option<RoutingRequest>,
    ) -> Arc<Self> {
        let request = if local { None } else { request };
        Arc::new(Self {
            router,
            platform,
            provider_id,
            local,
            inventory: Mutex::new(
                request
                    .as_ref()
                    .and_then(|request| request.inventory.clone()),
            ),
            initial: request,
            on_close: Mutex::default(),
        })
    }

    pub(crate) fn on_close(&self, callback: Arc<dyn Fn() + Send + Sync>) {
        *self.on_close.lock().unwrap() = Some(callback);
    }

    /// Selects hedging through the SDK without a host ranking callback.
    pub fn options(&self, model: String) -> RequestOptions {
        let local = self.local;
        let hedge = if local {
            None
        } else {
            self.initial.as_ref().and_then(|request| {
                let next = self.router.hedge_candidate(
                    request.clone(),
                    model.clone(),
                    self.platform.wall_time(),
                )?;
                let delay_ms = (self.router.hedge_delay(model.clone()) * 1000.0) as u32;
                Some(RequestHedge {
                    model: next.model,
                    delay_ms,
                })
            })
        };
        RequestOptions {
            model,
            local,
            routed: !local && self.initial.is_some(),
            hedge,
            ceiling_ms: 20_000,
            max_buffered_bytes: 1_048_576,
        }
    }

    /// Starts a request using existing foreground limits and the shared router.
    pub async fn start(self: Arc<Self>, model: String) -> Result<InferenceRequest, RequestError> {
        let started = crate::clock::now();
        let options = self.options(model);
        InferenceRequest::open_at(options, self, started).await
    }

    fn record(&self, model: String, result: RoutingResult) {
        self.router.record(
            RoutingOutcome {
                provider_id: self.provider_id.clone(),
                model,
                first_token_seconds: None,
                tokens_per_second: None,
                result,
            },
            self.platform.wall_time(),
        );
    }
}

impl RequestEffects for RoutedRequestEffects {
    fn reported(
        &self,
        report: Option<crate::inference::request_driver::RequestReport>,
        result: crate::inference::routing::RoutingResult,
    ) {
        self.platform.reported(report, result);
    }

    fn close(&self) {
        let callback = self.on_close.lock().unwrap().take();
        if let Some(callback) = callback {
            callback();
        }
    }

    fn prepare(
        &self,
        id: u64,
        model: String,
    ) -> BoxFuture<'_, Result<Option<CatalogReasoningEffort>, RequestError>> {
        async move {
            self.platform.validate(id, model.clone()).await?;
            // Dispatch effort uses the original request, even after catalog refresh.
            Ok(self
                .initial
                .as_ref()
                .and_then(|request| self.router.reasoning_effort(request.clone(), model)))
        }
        .boxed()
    }

    fn open(
        &self,
        id: u64,
        model: String,
        effort: Option<CatalogReasoningEffort>,
    ) -> BoxFuture<'_, Result<Arc<dyn RequestCandidate>, RequestError>> {
        self.platform.open(id, model, effort)
    }

    fn cancel(&self, id: u64) {
        self.platform.cancel(id);
    }

    fn record_failure(&self, model: String, error: RequestError) {
        let result = if error.cancelled() {
            RoutingResult::Cancelled
        } else {
            RoutingResult::Failed {
                failure: error.routing_failure(),
            }
        };
        self.record(model, result);
    }

    fn refresh_catalog(&self) -> BoxFuture<'_, ()> {
        async move {
            let Some(updated) = self
                .platform
                .refresh_catalog(self.provider_id.clone())
                .await
            else {
                return;
            };
            let mut inventory = self.inventory.lock().unwrap();
            if let Some(current) = inventory.as_mut() {
                // Discovery updates offers/settings; the request retains its provider endpoint.
                current.available = updated.available;
                current.enabled = updated.enabled;
                current.models = updated.models;
            }
        }
        .boxed()
    }

    fn rank_replacement(
        &self,
        model: String,
        error: RequestError,
    ) -> BoxFuture<'_, Option<String>> {
        async move {
            let now = self.platform.wall_time();
            let mut request = self.initial.clone()?;
            request.current_model = model;
            request.inventory = self.inventory.lock().unwrap().clone();
            // Capture demand before host health work can interleave another turn.
            let demand = self.router.replacement_demand(request.clone());
            if !request.automatic || request.inventory.is_none() {
                return None;
            }
            let observations = self.platform.refresh_health(self.provider_id.clone()).await;
            self.router
                .replace_remote_health(self.provider_id.clone(), observations);
            self.router
                .replacement(
                    request,
                    error.routing_failure(),
                    Some(demand),
                    now,
                    self.platform.wall_time(),
                )
                .map(|decision| decision.model)
        }
        .boxed()
    }

    fn record_loser(&self, model: String, _silent_ms: u64) {
        self.router
            .record_hedge_loss(model, self.platform.wall_time());
    }

    fn record_outcome(&self, report: super::RequestReport) {
        self.router.record(
            RoutingOutcome {
                provider_id: self.provider_id.clone(),
                model: report.model,
                first_token_seconds: report.first_token_seconds,
                tokens_per_second: report.tokens_per_second,
                result: report.result,
            },
            self.platform.wall_time(),
        );
    }
}
