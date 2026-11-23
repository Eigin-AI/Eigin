pub(super) use super::super::state::decision;
use super::super::*;

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

pub(super) fn request() -> RoutingRequest {
    RoutingRequest {
        provider_id: "provider".into(),
        current_model: "a".into(),
        automatic: true,
        conversation_id: None,
        message_needs_reasoning: false,
        requirements: RoutingRequirements {
            needs_tools: true,
            needs_vision: false,
            prompt_tokens: None,
        },
        inventory: Some(RoutingInventory {
            provider_id: "provider".into(),
            base_url: "https://provider.test".into(),
            available: vec!["a".into(), "b".into()],
            enabled: vec![],
            models: vec![model("a", 0), model("b", 1)],
        }),
    }
}

pub(super) fn outcome(model: &str, result: RoutingResult) -> RoutingOutcome {
    RoutingOutcome {
        provider_id: "provider".into(),
        model: model.into(),
        first_token_seconds: None,
        tokens_per_second: None,
        result,
    }
}

pub(super) fn failed(failure: RoutingFailure) -> RoutingResult {
    RoutingResult::Failed { failure }
}

pub(super) fn sample(value: f64, observed_at: f64) -> RoutingHealthSample {
    RoutingHealthSample {
        value,
        observed_at,
        expires_at: 100.0,
        count: 3,
        probe: false,
    }
}

pub(super) fn remote(ttft: Vec<RoutingHealthSample>) -> RoutingRemoteHealth {
    RoutingRemoteHealth {
        model: "a".into(),
        ttft,
        tps: vec![],
        failures: vec![],
    }
}
