use super::*;
use crate::{
    agent::{AgentRound, RoundError, TurnAction, TurnContinuation, TurnFailure},
    inference::{
        InferenceError,
        request_driver::{InferenceRequest, RequestError},
        routing::RoutingResult,
    },
};

impl ChatTurn {
    pub(super) async fn recover_request(
        &self,
        error: ChatTurnError,
        round: &AgentRound,
        request: &mut InferenceRequest,
        local: bool,
    ) -> Result<TurnContinuation, ChatTurnError> {
        if matches!(error, ChatTurnError::Stopped) {
            return Err(error);
        }
        let cancelled = matches!(&error, ChatTurnError::Stopped | ChatTurnError::Cancelled)
            || matches!(
                &error,
                ChatTurnError::Request(
                    RequestError::Inference(InferenceError::Cancelled)
                        | RequestError::Classified {
                            error: InferenceError::Cancelled,
                            ..
                        }
                )
            );
        if cancelled {
            let _ = self.report_request(request, RoutingResult::Cancelled).await;
            return if matches!(error, ChatTurnError::Stopped)
                || !self.input.propagate_stream_cancellation
            {
                Err(ChatTurnError::Stopped)
            } else {
                Err(ChatTurnError::Cancelled)
            };
        }
        let failure = match &error {
            ChatTurnError::Request(error) => error.routing_failure(),
            _ => crate::inference::routing::RoutingFailure::NotTheModelsFault,
        };
        self.report_request(request, RoutingResult::Failed { failure })
            .await?;
        let classification = match &error {
            ChatTurnError::Round(RoundError::Interrupted) => TurnFailure::Interruption,
            ChatTurnError::Request(RequestError::MissingReply) => TurnFailure::MissingReply,
            ChatTurnError::Request(error) => self.host.classify_failure(error),
            _ => TurnFailure::Terminal,
        };
        let mut signals = self.signals(TurnSignalBoundary::Failure).await?;
        if classification == TurnFailure::MissingReply {
            signals = self.signals(TurnSignalBoundary::Failure).await?;
        }
        match self.progression.fail_round(
            classification,
            signals,
            self.input.allow_interruption_recovery && !local,
        )? {
            TurnAction::Recover { reason } => {
                self.recover(reason, round).await?;
                Ok(reason)
            }
            TurnAction::ReturnStopped => Err(ChatTurnError::Stopped),
            _ => Err(error),
        }
    }
}
