use super::*;
use crate::agent::TurnOutputEntry;
use crate::inference::routing::ModelRouter;

/// A complete turn with stop and checkpoint access while host capabilities are suspended.
#[derive(uniffi::Object)]
pub struct ChatTurnOperation {
    turn: Arc<ChatTurn>,
    host: Arc<host::Host>,
    started: AtomicBool,
}
#[uniffi::export]
impl ChatTurnOperation {
    #[uniffi::constructor]
    pub fn new(
        input: ChatTurnInput,
        router: Arc<ModelRouter>,
        host: Box<dyn TurnHost>,
    ) -> Arc<Self> {
        let host = host::Host::new(host);
        Arc::new(Self {
            turn: ChatTurn::new(input, router, host.clone()),
            host,
            started: AtomicBool::new(false),
        })
    }

    /// Starts once; a concurrent second call cannot cancel the active turn.
    pub async fn run(&self) -> Result<Vec<TurnOutputEntry>, ChatTurnError> {
        if self.started.swap(true, Ordering::AcqRel) {
            return Err(ChatTurnError::AlreadyStarted);
        }
        let _scope = HostScope(self.host.clone());
        self.turn.run().await
    }

    /// Stops admission before cancelling callbacks and returns the immediate checkpoint.
    pub fn stop(&self) -> Vec<TurnOutputEntry> {
        let checkpoint = self.turn.stop();
        self.host.close();
        checkpoint
    }
    pub fn cancel(&self) {
        self.turn.cancel();
        self.host.close();
    }
    pub fn checkpoint(&self) -> Vec<TurnOutputEntry> {
        self.turn.checkpoint()
    }
    pub fn retained_output(&self) -> Vec<TurnOutputEntry> {
        self.turn.retained_output()
    }
    pub fn rounds_executed(&self) -> u32 {
        self.turn.rounds_executed()
    }
    pub fn partial_content(&self) -> String {
        self.turn.partial_content()
    }
    pub fn active_model(&self) -> String {
        self.turn.active_model()
    }
}
impl Drop for ChatTurnOperation {
    fn drop(&mut self) {
        self.cancel();
    }
}
struct HostScope(Arc<host::Host>);
impl Drop for HostScope {
    fn drop(&mut self) {
        self.0.close();
    }
}

/// Inline execution remains tied to the original operation and round.
#[derive(uniffi::Object)]
pub struct InlineTurnOperation(pub(super) Arc<InlineTurnTools>);
#[uniffi::export]
impl InlineTurnOperation {
    pub async fn execute(&self, call: InferenceToolCall) -> LocalToolResult {
        self.0.execute(call).await
    }
}
