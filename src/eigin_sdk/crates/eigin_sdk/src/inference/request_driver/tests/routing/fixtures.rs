use super::*;

#[derive(Default)]
pub(super) struct Platform {
    pub(super) execution: Arc<Effects>,
    pub(super) log: Mutex<Vec<String>>,
    pub(super) inventory: Mutex<Option<RoutingInventory>>,
    pub(super) health: Mutex<Vec<RoutingRemoteHealth>>,
    pub(super) health_wait: Mutex<Option<oneshot::Receiver<()>>>,
    pub(super) clock: Mutex<f64>,
    pub(super) efforts: Mutex<Vec<(String, Option<CatalogReasoningEffort>)>>,
}

impl RequestPlatform for Platform {
    fn validate(&self, id: u64, model: String) -> BoxFuture<'_, Result<(), RequestError>> {
        async move {
            self.log.lock().unwrap().push(format!("validate:{model}"));
            self.execution.prepare(id, model).await.map(|_| ())
        }
        .boxed()
    }

    fn open(
        &self,
        id: u64,
        model: String,
        effort: Option<CatalogReasoningEffort>,
    ) -> BoxFuture<'_, Result<Arc<dyn RequestCandidate>, RequestError>> {
        self.efforts.lock().unwrap().push((model.clone(), effort));
        self.execution.open(id, model, effort)
    }

    fn cancel(&self, id: u64) {
        self.execution.cancel(id);
    }

    fn refresh_catalog(&self, provider_id: String) -> BoxFuture<'_, Option<RoutingInventory>> {
        async move {
            self.log
                .lock()
                .unwrap()
                .push(format!("catalog:{provider_id}"));
            self.inventory.lock().unwrap().clone()
        }
        .boxed()
    }

    fn refresh_health(&self, provider_id: String) -> BoxFuture<'_, Vec<RoutingRemoteHealth>> {
        async move {
            self.log
                .lock()
                .unwrap()
                .push(format!("health:{provider_id}"));
            let wait = self.health_wait.lock().unwrap().take();
            if let Some(wait) = wait {
                let _ = wait.await;
            }
            self.health.lock().unwrap().clone()
        }
        .boxed()
    }

    fn wall_time(&self) -> f64 {
        *self.clock.lock().unwrap()
    }
}

pub(super) fn model(id: &str, rank: u64) -> RoutingModel {
    RoutingModel {
        id: id.into(),
        rank: Some(rank),
        supports_tools: true,
        supports_vision: true,
        supports_reasoning: false,
        context_window: 128_000,
        max_output: None,
        reasoning_control: None,
    }
}

pub(super) fn route() -> RoutingRequest {
    RoutingRequest {
        provider_id: "provider".into(),
        current_model: "a".into(),
        automatic: true,
        conversation_id: Some("conversation".into()),
        message_needs_reasoning: false,
        requirements: RoutingRequirements {
            needs_tools: true,
            needs_vision: false,
            prompt_tokens: Some(100),
        },
        inventory: Some(RoutingInventory {
            provider_id: "provider".into(),
            base_url: "https://provider.test".into(),
            available: vec!["a".into(), "b".into(), "c".into()],
            enabled: vec![],
            models: vec![model("a", 0), model("b", 1), model("c", 2)],
        }),
    }
}

pub(super) fn setup(
    request: RoutingRequest,
) -> (Arc<ModelRouter>, Arc<Platform>, Arc<RoutedRequestEffects>) {
    let router = ModelRouter::new();
    let platform = Arc::new(Platform::default());
    let effects = RoutedRequestEffects::new(
        router.clone(),
        platform.clone(),
        "provider".into(),
        false,
        Some(request),
    );
    (router, platform, effects)
}

pub(super) fn classified(failure: RoutingFailure) -> RequestError {
    RequestError::Classified {
        error: InferenceError::Http {
            status: 503,
            body: None,
        },
        failure,
    }
}

pub(super) fn diagnostics_lock() -> std::sync::MutexGuard<'static, ()> {
    crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap()
}
