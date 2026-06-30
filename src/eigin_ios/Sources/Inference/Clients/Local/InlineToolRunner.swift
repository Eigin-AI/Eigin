import Foundation

/// An inline tool runner is a closure that executes a tool call mid-stream,
/// inside the model's own generation loop.
///
/// Unlike the cloud path — where the chat loop streams a full round, waits for
/// `finish_reason: tool_calls`, then executes tools and re-streams — an inline
/// runner is invoked by the runtime *while the stream is still open*, before
/// the model produces its final prose response. LiteRT-LM owns this loop
/// internally: it calls `run()` on each bridged tool, awaits the result, feeds
/// it back into the same KV-cached session, and continues generating — all
/// inside a single `sendMessageStream` call.
///
/// The runner is responsible for the full execution lifecycle: permission
/// resolution, tool execution, and recording the round (assistant tool-call
/// message + tool result message) into whatever history store the caller
/// maintains. It returns the `ToolResult` so the runtime can feed the content
/// back to LiteRT.
///
/// ## Naming
///
/// "Inline" contrasts with the cloud loop's "round-trip" model: instead of
/// finishing the stream and opening a new one for the next round, the runtime
/// executes tools inline and the stream ends only when the model truly stops.
struct InlineToolRunner: Sendable {
    /// Execute a tool call and return its result.
    ///
    /// Runs on the main actor — matching `ToolExecutor.execute` and the chat
    /// loop's `@MainActor` isolation — so the closure can touch UI state,
    /// update permissions, and append messages to the loop's history.
    let run: @MainActor @Sendable (ToolCall) async -> ToolResult
}
