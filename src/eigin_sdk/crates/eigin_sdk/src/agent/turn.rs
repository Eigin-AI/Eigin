use super::RoundOutcome;
use std::sync::Mutex;

const ROUND_LIMIT: u32 = 40;

/// Host lifecycle facts sampled at a progression boundary, not cancellation mechanics.
#[derive(Clone, Copy, Debug, Default, uniffi::Record)]
pub struct TurnSignals {
    pub cancelled: bool,
    pub stopped: bool,
    pub terminate: bool,
}

/// Adapter-classified failure; the host retains the original error for propagation.
#[derive(Clone, Copy, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum TurnFailure {
    MissingReply,
    Interruption,
    Terminal,
}

/// Semantic instruction for the next request only.
#[derive(Clone, Copy, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum TurnContinuation {
    MissingReply,
    Interrupted,
}

/// Why the host can return the accumulated transcript.
#[derive(Clone, Copy, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum TurnFinishReason {
    Reply,
    ExplicitTermination,
    RoundLimit,
}

/// Host work selected by the turn. Recovery always discards unfinished calls and retains completed work.
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum TurnAction {
    RequestInference,
    CheckEmptyReply,
    ExecuteTools,
    Continue,
    Finish { reason: TurnFinishReason },
    Recover { reason: TurnContinuation },
    MissingReply,
    PropagateFailure,
    ReturnStopped,
    Cancelled,
}

/// Invalid sequencing of turn operations.
#[derive(Debug, PartialEq, Eq, thiserror::Error, uniffi::Error)]
pub enum TurnError {
    #[error("Operation is invalid in the current turn phase")]
    InvalidPhase,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Phase {
    Ready,
    Inference,
    EmptyReply,
    Tools,
    Done,
}

struct State {
    phase: Phase,
    rounds: u32,
    recovery_used: bool,
}

/// One transient turn's progression and shared recovery budget. Hosts perform all returned work.
#[derive(uniffi::Object)]
pub struct AgentTurn {
    state: Mutex<State>,
}

impl Default for AgentTurn {
    fn default() -> Self {
        Self::new()
    }
}

#[uniffi::export]
impl AgentTurn {
    /// Starts a turn with the existing forty-request budget and one recovery allowance.
    #[uniffi::constructor]
    pub fn new() -> Self {
        Self {
            state: Mutex::new(State {
                phase: Phase::Ready,
                rounds: 0,
                recovery_used: false,
            }),
        }
    }

    /// Requests inference or finishes at the round limit after host tool refresh.
    pub fn begin_round(&self) -> Result<TurnAction, TurnError> {
        let mut state = self.state.lock().unwrap();
        require_phase(&state, Phase::Ready)?;
        if state.rounds == ROUND_LIMIT {
            state.phase = Phase::Done;
            return Ok(TurnAction::Finish {
                reason: TurnFinishReason::RoundLimit,
            });
        }
        state.rounds += 1;
        state.phase = Phase::Inference;
        Ok(TurnAction::RequestInference)
    }

    /// Number of reserved inference requests, including the current request.
    pub fn rounds_executed(&self) -> u32 {
        self.state.lock().unwrap().rounds
    }

    /// Decides what follows a completed SDK round. The host retains its outcome payload.
    pub fn complete_round(&self, outcome: RoundOutcome) -> Result<TurnAction, TurnError> {
        let mut state = self.state.lock().unwrap();
        require_phase(&state, Phase::Inference)?;
        let action = match outcome {
            RoundOutcome::Tools { .. } => TurnAction::ExecuteTools,
            RoundOutcome::Reply { message }
                if !message
                    .content
                    .as_deref()
                    .unwrap_or_default()
                    .chars()
                    .all(reply_whitespace) =>
            {
                TurnAction::Finish {
                    reason: TurnFinishReason::Reply,
                }
            }
            _ => TurnAction::CheckEmptyReply,
        };
        transition(&mut state, &action);
        Ok(action)
    }

    /// Samples host termination only when a completed round lacks usable prose.
    pub fn resolve_empty_reply(&self, signals: TurnSignals) -> Result<TurnAction, TurnError> {
        let mut state = self.state.lock().unwrap();
        require_phase(&state, Phase::EmptyReply)?;
        let action = if signals.stopped {
            TurnAction::ReturnStopped
        } else if signals.terminate {
            TurnAction::Finish {
                reason: TurnFinishReason::ExplicitTermination,
            }
        } else if signals.cancelled {
            TurnAction::Cancelled
        } else {
            recover(&mut state, TurnContinuation::MissingReply)
        };
        transition(&mut state, &action);
        Ok(action)
    }

    /// Applies recovery policy to a failed stream. Local hosts disable interruption recovery.
    pub fn fail_round(
        &self,
        failure: TurnFailure,
        signals: TurnSignals,
        allow_interruption_recovery: bool,
    ) -> Result<TurnAction, TurnError> {
        let mut state = self.state.lock().unwrap();
        require_phase(&state, Phase::Inference)?;
        let interrupted = signals.cancelled || signals.stopped || signals.terminate;
        let action = match failure {
            TurnFailure::MissingReply if interrupted => TurnAction::ReturnStopped,
            TurnFailure::MissingReply => recover(&mut state, TurnContinuation::MissingReply),
            TurnFailure::Interruption if !interrupted && allow_interruption_recovery => {
                recover(&mut state, TurnContinuation::Interrupted)
            }
            _ => TurnAction::PropagateFailure,
        };
        transition(&mut state, &action);
        Ok(action)
    }

    /// Completes host tool execution. Refresh host tools after Continue, even at the round limit.
    pub fn complete_tools(&self, terminate: bool) -> Result<TurnAction, TurnError> {
        let mut state = self.state.lock().unwrap();
        require_phase(&state, Phase::Tools)?;
        let action = if terminate {
            TurnAction::Finish {
                reason: TurnFinishReason::ExplicitTermination,
            }
        } else {
            TurnAction::Continue
        };
        transition(&mut state, &action);
        Ok(action)
    }
}

fn require_phase(state: &State, phase: Phase) -> Result<(), TurnError> {
    if state.phase == phase {
        Ok(())
    } else {
        Err(TurnError::InvalidPhase)
    }
}

fn recover(state: &mut State, reason: TurnContinuation) -> TurnAction {
    if state.recovery_used || state.rounds == ROUND_LIMIT {
        return match reason {
            TurnContinuation::MissingReply => TurnAction::MissingReply,
            TurnContinuation::Interrupted => TurnAction::PropagateFailure,
        };
    }
    state.recovery_used = true;
    TurnAction::Recover { reason }
}

fn transition(state: &mut State, action: &TurnAction) {
    state.phase = match action {
        TurnAction::CheckEmptyReply => Phase::EmptyReply,
        TurnAction::ExecuteTools => Phase::Tools,
        TurnAction::Continue | TurnAction::Recover { .. } => Phase::Ready,
        _ => Phase::Done,
    };
}

// Foundation whitespacesAndNewlines includes zero-width space; Rust's is_whitespace does not.
fn reply_whitespace(c: char) -> bool {
    c.is_whitespace() || c == '\u{200b}'
}
