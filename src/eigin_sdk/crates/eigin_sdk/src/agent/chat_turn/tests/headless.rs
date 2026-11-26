use super::*;

struct HeadlessHost(Host);

impl ChatTurnHost for HeadlessHost {
    fn prepare(
        &self,
        context: TurnContext,
        inline: Arc<InlineTurnTools>,
    ) -> BoxFuture<'_, Result<PreparedTurnRequest, RequestError>> {
        self.0.prepare(context, inline)
    }

    fn execute(&self, call: InferenceToolCall) -> BoxFuture<'_, LocalToolResult> {
        self.0.execute(call)
    }

    fn refresh_tools(&self) -> BoxFuture<'_, Option<Vec<InferenceToolDefinition>>> {
        self.0.refresh_tools()
    }

    fn signals(&self, boundary: TurnSignalBoundary) -> BoxFuture<'_, TurnSignals> {
        self.0.signals(boundary)
    }

    fn classify_failure(&self, error: &RequestError) -> TurnFailure {
        self.0.classify_failure(error)
    }
}

#[test]
fn headless_turn_runs_tools_and_finishes_without_presentation_or_observation() {
    block_on(async {
        let host = Arc::new(HeadlessHost(Host::default()));
        host.0.scripts.lock().unwrap().extend([
            batch(&["a"]),
            Script::events(vec![text("answer"), finish()]),
        ]);
        let output = operation(host.clone()).run().await.unwrap();
        assert_eq!(*host.0.calls.lock().unwrap(), ["a"]);
        assert_eq!(
            output
                .iter()
                .map(|entry| entry.message.role.as_str())
                .collect::<Vec<_>>(),
            ["assistant", "tool", "assistant"]
        );
        assert_eq!(
            output.last().unwrap().message.content.as_deref(),
            Some("answer")
        );
    });
}
