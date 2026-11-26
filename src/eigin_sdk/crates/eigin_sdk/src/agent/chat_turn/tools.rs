use super::*;
use crate::{
    agent::{AgentRound, RoundToolResult, TurnAction},
    conversation::ConversationMessage,
    inference::InferenceToolCall,
};

impl ChatTurn {
    pub(super) async fn execute_tools(
        &self,
        round: &AgentRound,
        assistant: ConversationMessage,
        calls: Vec<InferenceToolCall>,
    ) -> Result<TurnAction, ChatTurnError> {
        self.active_state()?.output.begin_tools()?;
        self.present(TurnPresentation::FinishToolProse {
            has_prose: !round.partial_content().is_empty(),
        })
        .await?;
        let entry = self.active_state()?.output.record_batch(assistant)?;
        self.notify(ChatTurnEvent::Output {
            entries: vec![entry],
        })
        .await?;
        for call in calls {
            self.present(TurnPresentation::BeforeTool { call: call.clone() })
                .await?;
            let result = self.wait(self.host.execute(call)).await?;
            self.present(TurnPresentation::AfterTool).await?;
            let entry = self
                .active_state()?
                .output
                .record_result(round.record_result(RoundToolResult {
                    tool_call_id: result.tool_call_id,
                    content: result.content,
                })?)?;
            self.notify(ChatTurnEvent::Output {
                entries: vec![entry],
            })
            .await?;
        }
        Ok(self.progression.complete_tools(
            self.signals(TurnSignalBoundary::ToolsCompleted)
                .await?
                .terminate,
        )?)
    }
}
