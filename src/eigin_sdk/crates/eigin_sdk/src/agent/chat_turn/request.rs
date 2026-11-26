use super::*;
use crate::{
    agent::{AgentRound, TurnContinuation},
    inference::{
        InferenceToolDefinition,
        request_driver::{InferenceRequest, RoutedRequestEffects},
    },
};
use std::sync::{Arc, atomic::AtomicBool};

pub(super) struct RoundRequest {
    pub round: Arc<AgentRound>,
    pub request: InferenceRequest,
    pub local: bool,
}

impl ChatTurn {
    pub(super) async fn open_round(
        self: &Arc<Self>,
        tools: &Option<Vec<InferenceToolDefinition>>,
        initial_instruction: &Option<String>,
        continuation: Option<TurnContinuation>,
    ) -> Result<RoundRequest, ChatTurnError> {
        self.ensure_active()?;
        let round = Arc::new(AgentRound::new());
        let context = {
            let mut state = self.active_state()?;
            state.round = Some(round.clone());
            TurnContext {
                initial_messages: self.input.messages.clone(),
                output: state.output.output(),
                tools: tools.clone(),
                model: state.model.clone(),
                initial_instruction: initial_instruction.clone(),
                continuation,
            }
        };
        let inline = Arc::new(InlineTurnTools {
            turn: Arc::downgrade(self),
            round: round.clone(),
            closed: AtomicBool::new(false),
        });
        let prepared = self
            .wait(self.host.prepare(context, inline.clone()))
            .await??;
        let effects = RoutedRequestEffects::new(
            self.router.clone(),
            prepared.platform,
            prepared.provider_id,
            prepared.local,
            prepared.routing,
        );
        effects.on_close(Arc::new(move || inline.close()));
        let request = self.wait(effects.start(self.active_model())).await??;
        self.active_state()?.request = Some(request.cancellation());
        self.notify(ChatTurnEvent::RequestOpened).await?;
        Ok(RoundRequest {
            round,
            request,
            local: prepared.local,
        })
    }
}
