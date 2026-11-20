use super::{CheckpointOrigin, CheckpointProgress, RoundError, agent_build_checkpoint};
use crate::conversation::ConversationMessage;
use std::sync::Mutex;

/// Output provenance; hosts map it to presentation identities.
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum TurnOutputOrigin {
    /// Turn-local identity retained when a draft becomes a recorded message.
    Recorded { id: u64 },
    /// Position of a synthesized uncertainty result in this checkpoint snapshot.
    InterruptedTool { index: u64 },
}

/// Ordered output with identity independent of its content.
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct TurnOutputEntry {
    pub message: ConversationMessage,
    pub origin: TurnOutputOrigin,
}

#[derive(Default)]
struct OutputState {
    entries: Vec<TurnOutputEntry>,
    retained: usize,
    next_id: u64,
    draft: Option<u64>,
    partial: String,
    draft_index: Option<u64>,
    executing: bool,
    batch_recorded: bool,
    done: bool,
}

impl OutputState {
    fn allocate(&mut self) -> u64 {
        let id = self.next_id;
        self.next_id += 1;
        id
    }

    fn append(&mut self, message: ConversationMessage, draft: bool) -> TurnOutputEntry {
        let id = if draft {
            self.draft_index = Some(self.entries.len() as u64);
            self.draft.unwrap_or_else(|| self.allocate())
        } else {
            self.allocate()
        };
        let entry = TurnOutputEntry {
            message,
            origin: TurnOutputOrigin::Recorded { id },
        };
        self.entries.push(entry.clone());
        entry
    }
}

/// Owns ordered turn output and retention; hosts execute tools and persist snapshots.
#[derive(Default, uniffi::Object)]
pub struct AgentTurnOutput {
    state: Mutex<OutputState>,
}

#[uniffi::export]
impl AgentTurnOutput {
    /// Creates empty output for a turn.
    #[uniffi::constructor]
    pub fn new() -> Self {
        Self::default()
    }

    /// Starts a new prose identity while retaining earlier output.
    pub fn begin_draft(&self) -> Result<u64, RoundError> {
        let mut state = self.state.lock().unwrap();
        if state.done {
            return Err(RoundError::InvalidPhase);
        }
        let id = state.allocate();
        state.draft = Some(id);
        state.partial.clear();
        state.draft_index = None;
        state.executing = false;
        state.batch_recorded = false;
        Ok(id)
    }

    /// Supplies the current round's accumulated prose.
    pub fn update_draft(&self, content: String) -> Result<(), RoundError> {
        let mut state = self.state.lock().unwrap();
        if state.done || state.draft.is_none() {
            return Err(RoundError::InvalidPhase);
        }
        state.partial = content;
        Ok(())
    }

    /// Marks tool execution before the host drains its presentation buffers.
    pub fn begin_tools(&self) -> Result<(), RoundError> {
        let mut state = self.state.lock().unwrap();
        if state.done {
            return Err(RoundError::InvalidPhase);
        }
        state.executing = true;
        Ok(())
    }

    /// Records the completed cloud assistant batch before executing its calls.
    pub fn record_batch(
        &self,
        message: ConversationMessage,
    ) -> Result<TurnOutputEntry, RoundError> {
        let mut state = self.state.lock().unwrap();
        if state.done
            || message.tool_calls.as_ref().is_none_or(Vec::is_empty)
            || state.draft_index.is_some()
            || state.batch_recorded
        {
            return Err(RoundError::InvalidPhase);
        }
        let has_prose = !state.partial.is_empty();
        let entry = state.append(message, has_prose);
        state.retained = state.entries.len();
        state.executing = true;
        state.batch_recorded = true;
        Ok(entry)
    }

    /// Records a result already accepted by the round's execution ordering.
    pub fn record_result(
        &self,
        message: ConversationMessage,
    ) -> Result<TurnOutputEntry, RoundError> {
        if message.role != "tool" {
            return Err(RoundError::InvalidPhase);
        }
        let mut state = self.state.lock().unwrap();
        let entry = state.append(message, false);
        state.retained = state.entries.len();
        Ok(entry)
    }

    /// Records a completed inline exchange atomically without sealing prose.
    pub fn record_inline_exchange(
        &self,
        messages: Vec<ConversationMessage>,
    ) -> Result<Vec<TurnOutputEntry>, RoundError> {
        if messages.len() != 2 || messages[0].role != "assistant" || messages[1].role != "tool" {
            return Err(RoundError::InvalidPhase);
        }
        let mut state = self.state.lock().unwrap();
        let entries = messages
            .into_iter()
            .map(|message| state.append(message, false))
            .collect();
        state.retained = state.entries.len();
        Ok(entries)
    }

    /// Seals interrupted prose once before a recovery draft begins.
    pub fn retain_interrupted_prose(&self) -> Result<Option<TurnOutputEntry>, RoundError> {
        let mut state = self.state.lock().unwrap();
        if state.done {
            return Err(RoundError::InvalidPhase);
        }
        if state.partial.is_empty() || state.draft_index.is_some() {
            return Ok(None);
        }
        let message = ConversationMessage {
            role: "assistant".into(),
            content: Some(state.partial.clone()),
            ..Default::default()
        };
        let entry = state.append(message, true);
        state.retained = state.entries.len();
        Ok(Some(entry))
    }

    /// Completes output while keeping final prose outside the live committed rows.
    pub fn finish(&self, message: Option<ConversationMessage>) -> Result<(), RoundError> {
        let mut state = self.state.lock().unwrap();
        if state.done || (message.is_some() && state.draft_index.is_some()) {
            return Err(RoundError::InvalidPhase);
        }
        if let Some(message) = message {
            state.append(message, true);
        }
        state.done = true;
        Ok(())
    }

    /// Returns all recorded output in order.
    pub fn output(&self) -> Vec<TurnOutputEntry> {
        self.state.lock().unwrap().entries.clone()
    }

    /// Returns the live display prefix, excluding final prose until settlement.
    pub fn retained_output(&self) -> Vec<TurnOutputEntry> {
        let state = self.state.lock().unwrap();
        state.entries[..state.retained].to_vec()
    }

    /// Reads a stop/failure snapshot without changing live output or admitting results.
    pub fn checkpoint(&self) -> Vec<TurnOutputEntry> {
        let state = self.state.lock().unwrap();
        let progress = CheckpointProgress {
            retained_count: state.retained as u64,
            is_done: state.done,
            is_executing_tools: state.executing,
            partial_content: state.partial.clone(),
            current_message_index: state.draft_index,
        };
        agent_build_checkpoint(
            state
                .entries
                .iter()
                .map(|entry| entry.message.clone())
                .collect(),
            progress,
        )
        .into_iter()
        .enumerate()
        .map(|(index, entry)| TurnOutputEntry {
            message: entry.message,
            origin: match entry.origin {
                CheckpointOrigin::Produced { index } => {
                    state.entries[index as usize].origin.clone()
                }
                CheckpointOrigin::PartialProse => TurnOutputOrigin::Recorded {
                    id: state.draft.expect("partial prose has a draft"),
                },
                CheckpointOrigin::InterruptedTool => TurnOutputOrigin::InterruptedTool {
                    index: index as u64,
                },
            },
        })
        .collect()
    }
}
