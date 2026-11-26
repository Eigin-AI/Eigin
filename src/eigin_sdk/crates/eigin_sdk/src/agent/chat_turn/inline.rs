use super::operation::State;
use super::*;
use crate::agent::AgentRound;
use crate::{
    agent::RoundToolResult,
    inference::{InferenceToolCall, local::LocalToolResult},
};
use std::sync::Weak;
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};

/// Executes inline tools against their original round and returns results to the same generation.
pub struct InlineTurnTools {
    pub(super) turn: Weak<ChatTurn>,
    pub(super) round: Arc<AgentRound>,
    pub(super) closed: AtomicBool,
}

impl InlineTurnTools {
    /// Completed side effects return their result even when stop prevents transcript admission.
    pub async fn execute(&self, call: InferenceToolCall) -> LocalToolResult {
        let rejected = || LocalToolResult {
            tool_call_id: call.id.clone(),
            content: "{}".into(),
            is_error: true,
        };
        let Some(turn) = self.turn.upgrade() else {
            return rejected();
        };
        if !self.accepts(&turn.state.lock().unwrap()) {
            return rejected();
        }
        let result = turn.host.execute(call.clone()).await;
        let entries = {
            let state = turn.state.lock().unwrap();
            if !self.accepts(&state) {
                return result;
            }
            self.round
                .record_inline_exchange(
                    call,
                    RoundToolResult {
                        tool_call_id: result.tool_call_id.clone(),
                        content: result.content.clone(),
                    },
                )
                .and_then(|messages| state.output.record_inline_exchange(messages))
        };
        if let Ok(entries) = entries {
            let _ = turn.notify(ChatTurnEvent::Output { entries }).await;
        }
        result
    }

    pub(super) fn close(&self) {
        let turn = self.turn.upgrade();
        let _state = turn.as_ref().map(|turn| turn.state.lock().unwrap());
        self.closed.store(true, Ordering::Release);
    }

    fn accepts(&self, state: &State) -> bool {
        !self.closed.load(Ordering::Acquire)
            && !state.stopped
            && !state.cancelled
            && !state.closed
            && state
                .round
                .as_ref()
                .is_some_and(|round| Arc::ptr_eq(round, &self.round))
    }
}
