use super::{RoundError, RoundOutcome, RoundToolResult};
use crate::{
    conversation::{ASSISTANT_ROLE, ConversationMessage, TOOL_ROLE},
    inference::{
        InferenceEvent, InferenceFinishReason, InferenceReasoningHistory, InferenceToolCall,
    },
};
use std::{collections::HashMap, sync::Mutex};

#[derive(Default)]
struct RoundState {
    content: String,
    calls: Vec<InferenceToolCall>,
    metadata: Option<HashMap<String, String>>,
    reasoning: Option<InferenceReasoningHistory>,
    finish: Option<InferenceFinishReason>,
    closed: bool,
    next_result: Option<usize>,
}

/// One streamed reply and its tool exchanges, independent of execution and storage.
#[derive(Default, uniffi::Object)]
pub struct AgentRound {
    state: Mutex<RoundState>,
}

#[uniffi::export]
impl AgentRound {
    /// Starts an empty round. Drop the handle to discard unfinished output.
    #[uniffi::constructor]
    pub fn new() -> Self {
        Self::default()
    }

    /// Accumulates an ordered event without copying the accumulated reply.
    pub fn accept_event(&self, event: InferenceEvent) -> Result<(), RoundError> {
        let mut state = self.state.lock().unwrap();
        if state.closed {
            return Err(RoundError::InvalidPhase);
        }
        match event {
            InferenceEvent::ContentDelta { text } => state.content.push_str(&text),
            InferenceEvent::ToolCall { call } => state.calls.push(call),
            InferenceEvent::ProviderMetadata { values } => state.metadata = Some(values),
            InferenceEvent::ReasoningHistory { history } => state.reasoning = Some(history),
            InferenceEvent::Finished { reason } => state.finish = Some(reason),
            InferenceEvent::Performance { .. } => {}
        }
        Ok(())
    }

    /// Classifies exhausted output and validates a complete executable batch.
    pub fn finish_stream(&self) -> Result<RoundOutcome, RoundError> {
        let mut state = self.state.lock().unwrap();
        if state.closed {
            return Err(RoundError::InvalidPhase);
        }
        state.closed = true;
        let reason = state.finish.as_ref().ok_or(RoundError::Interrupted)?;
        if *reason == InferenceFinishReason::ToolCalls && !state.calls.is_empty() {
            if !state.calls.iter().all(valid_call) {
                return Err(RoundError::InvalidToolCall);
            }
            state.next_result = Some(0);
            return Ok(RoundOutcome::Tools {
                assistant: ConversationMessage {
                    role: ASSISTANT_ROLE.into(),
                    content: (!state.content.is_empty()).then(|| state.content.clone()),
                    tool_calls: Some(state.calls.clone()),
                    provider_metadata: state.metadata.clone(),
                    reasoning_history: state.reasoning.clone(),
                    ..Default::default()
                },
                calls: state.calls.clone(),
            });
        }
        if state.content.is_empty() && state.reasoning.is_none() {
            return Ok(RoundOutcome::Empty);
        }
        Ok(RoundOutcome::Reply {
            message: ConversationMessage {
                role: ASSISTANT_ROLE.into(),
                content: Some(state.content.clone()),
                reasoning_history: state.reasoning.clone(),
                ..Default::default()
            },
        })
    }

    /// Records the next sequential batch result, preserving the host-supplied ID.
    pub fn record_result(
        &self,
        result: RoundToolResult,
    ) -> Result<ConversationMessage, RoundError> {
        let mut state = self.state.lock().unwrap();
        let index = state.next_result.ok_or(RoundError::InvalidPhase)?;
        let call = state.calls.get(index).ok_or(RoundError::InvalidPhase)?;
        let message = tool_message(call, result);
        state.next_result = Some(index + 1);
        Ok(message)
    }

    /// Records an already executed local exchange without consuming streamed prose.
    pub fn record_inline_exchange(
        &self,
        call: InferenceToolCall,
        result: RoundToolResult,
    ) -> Result<Vec<ConversationMessage>, RoundError> {
        let state = self.state.lock().unwrap();
        if state.closed {
            return Err(RoundError::InvalidPhase);
        }
        let tool = tool_message(&call, result);
        Ok(vec![
            ConversationMessage {
                role: ASSISTANT_ROLE.into(),
                tool_calls: Some(vec![call]),
                ..Default::default()
            },
            tool,
        ])
    }

    /// Copies partial prose for host checkpoint or recovery decisions.
    pub fn partial_content(&self) -> String {
        self.state.lock().unwrap().content.clone()
    }

    /// Reports provider completion without finalizing or validating execution output.
    pub fn has_finished(&self) -> bool {
        self.state.lock().unwrap().finish.is_some()
    }

    /// Reports pending-call presence for host streaming presentation.
    pub fn has_tool_calls(&self) -> bool {
        !self.state.lock().unwrap().calls.is_empty()
    }
}

fn valid_call(call: &InferenceToolCall) -> bool {
    !call.id.is_empty() && !call.name.is_empty() && super::arguments::valid_object(&call.arguments)
}

fn tool_message(call: &InferenceToolCall, result: RoundToolResult) -> ConversationMessage {
    ConversationMessage {
        role: TOOL_ROLE.into(),
        content: Some(result.content),
        tool_call_id: Some(result.tool_call_id),
        name: Some(call.name.clone()),
        ..Default::default()
    }
}
