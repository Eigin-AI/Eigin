use super::running::Running;
use super::*;
use crate::agent::{AgentRound, TurnOutputEntry};
use crate::{
    agent::{RoundError, RoundOutcome, TurnAction, TurnContinuation},
    inference::{request_driver::InferenceRequest, routing::RoutingResult},
};
use std::sync::{Arc, atomic::Ordering};

impl ChatTurn {
    /// Runs automatic inference/tool/recovery continuation from the initial submission.
    /// Dropping this future closes the operation and rejects late inline completions.
    pub fn run(self: &Arc<Self>) -> ChatTurnFuture {
        if self.started.swap(true, Ordering::AcqRel) {
            return Box::pin(async { Err(ChatTurnError::AlreadyStarted) });
        }
        let turn = self.clone();
        Box::pin(Running {
            turn: self.clone(),
            work: Box::pin(async move { turn.drive().await }),
        })
    }

    async fn drive(self: &Arc<Self>) -> Result<Vec<TurnOutputEntry>, ChatTurnError> {
        let mut tools = self.input.tools.clone();
        let mut initial_instruction = self.input.initial_instruction.clone();
        let mut continuation = None;
        self.begin_draft().await?;
        loop {
            match self.progression.begin_round()? {
                TurnAction::RequestInference => {}
                TurnAction::Finish { .. } => break,
                _ => return Err(super::super::TurnError::InvalidPhase.into()),
            }
            let super::request::RoundRequest {
                round,
                mut request,
                local,
            } = self
                .open_round(&tools, &initial_instruction, continuation)
                .await?;
            initial_instruction = None;
            continuation = None;
            let streamed = self.consume(&round, &mut request).await;
            if let Err(error) = streamed {
                continuation = Some(
                    self.recover_request(error, &round, &mut request, local)
                        .await?,
                );
                continue;
            }
            self.report_request(&mut request, RoutingResult::Succeeded)
                .await?;
            self.ensure_active()?;
            let outcome = round.finish_stream()?;
            let mut action = self.progression.complete_round(outcome.clone())?;
            if matches!(action, TurnAction::CheckEmptyReply) {
                action = self
                    .progression
                    .resolve_empty_reply(self.signals(TurnSignalBoundary::EmptyReply).await?)?;
            }
            match (action, outcome) {
                (TurnAction::ExecuteTools, RoundOutcome::Tools { assistant, calls }) => {
                    match self.execute_tools(&round, assistant, calls).await? {
                        TurnAction::Finish { .. } => break,
                        TurnAction::Continue => {}
                        _ => return Err(super::super::TurnError::InvalidPhase.into()),
                    }
                    tools = self.wait(self.host.refresh_tools()).await?;
                    self.begin_draft().await?;
                }
                (TurnAction::Recover { reason }, _) => {
                    continuation = Some(reason);
                    self.begin_draft().await?;
                }
                (TurnAction::MissingReply, _) => return Err(ChatTurnError::MissingReply),
                (TurnAction::Cancelled, _) => return Err(ChatTurnError::Cancelled),
                (TurnAction::ReturnStopped, _) => return Err(ChatTurnError::Stopped),
                (TurnAction::Finish { .. }, outcome) => {
                    self.finish_output(outcome).await?;
                    break;
                }
                _ => return Err(super::super::TurnError::InvalidPhase.into()),
            }
        }
        Ok(self.active_state()?.output.output())
    }

    async fn finish_output(&self, outcome: RoundOutcome) -> Result<(), ChatTurnError> {
        self.present(TurnPresentation::Drain).await?;
        let message = match outcome {
            RoundOutcome::Reply { message } => Some(message),
            _ => None,
        };
        self.active_state()?.output.finish(message)?;
        self.notify(ChatTurnEvent::Finished).await?;
        Ok(())
    }

    pub(super) async fn report_request(
        &self,
        request: &mut InferenceRequest,
        result: RoutingResult,
    ) -> Result<(), ChatTurnError> {
        let report = request.report(result.clone());
        self.notify(ChatTurnEvent::RequestReported { report, result })
            .await
    }

    pub(super) async fn begin_draft(&self) -> Result<(), ChatTurnError> {
        let id = {
            let mut state = self.active_state()?;
            state.round = None;
            state.request = None;
            state.output.begin_draft()?
        };
        self.notify(ChatTurnEvent::Draft { id }).await
    }

    async fn consume(
        &self,
        round: &AgentRound,
        request: &mut InferenceRequest,
    ) -> Result<(), ChatTurnError> {
        let mut adopted = false;
        while let Some(event) = self.wait(request.next()).await?? {
            if !adopted {
                adopted = true;
                let model = request.attempts().winning_model();
                self.active_state()?.model = model.clone();
                self.notify(ChatTurnEvent::ModelSelected {
                    model,
                    retry: request.attempts().retry_won(),
                })
                .await?;
            }
            {
                let state = self.active_state()?;
                round.accept_event(event.clone())?;
                state.output.update_draft(round.partial_content())?;
                request.observe_output(&event);
            }
            self.notify(ChatTurnEvent::Inference { event }).await?;
        }
        if !round.has_finished() {
            return Err(RoundError::Interrupted.into());
        }
        Ok(())
    }

    pub(super) async fn recover(
        &self,
        reason: TurnContinuation,
        round: &AgentRound,
    ) -> Result<(), ChatTurnError> {
        if reason == TurnContinuation::Interrupted && !round.partial_content().is_empty() {
            self.present(TurnPresentation::Drain).await?;
            let retained = self.active_state()?.output.retain_interrupted_prose()?;
            if let Some(entry) = retained {
                self.notify(ChatTurnEvent::Output {
                    entries: vec![entry],
                })
                .await?;
            }
        }
        self.begin_draft().await
    }
}
