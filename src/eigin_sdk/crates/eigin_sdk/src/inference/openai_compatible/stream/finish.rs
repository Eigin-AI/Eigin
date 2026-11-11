use super::super::{adapters::Adapter, reasoning::ReasoningCapture, types::*};
use super::StreamParser;

impl StreamParser {
    pub(super) fn finish(&mut self, reason: &str) -> Result<(), InferenceError> {
        if self.refused {
            return Err(InferenceError::PolicyStop);
        }
        match reason {
            "length" => return Err(InferenceError::OutputLimit),
            "stop" | "tool_calls" => {}
            _ => return Err(InferenceError::PolicyStop),
        }
        if let Some(history) = self
            .reasoning
            .as_ref()
            .and_then(ReasoningCapture::completed)
        {
            self.events
                .push_back(InferenceEvent::ReasoningHistory { history });
        }
        let mut finish = InferenceFinishReason::Stop;
        if reason == "tool_calls"
            || (matches!(self.adapter, Adapter::Gemini) && !self.calls.is_empty())
        {
            if !self.metadata.is_empty() {
                self.events.push_back(InferenceEvent::ProviderMetadata {
                    values: std::mem::take(&mut self.metadata),
                });
            }
            for (_, call) in std::mem::take(&mut self.calls) {
                if !call.id.is_empty() && !call.name.is_empty() {
                    self.events.push_back(InferenceEvent::ToolCall { call });
                    finish = InferenceFinishReason::ToolCalls;
                }
            }
        }
        self.events
            .push_back(InferenceEvent::Finished { reason: finish });
        self.done = true;
        Ok(())
    }
}
