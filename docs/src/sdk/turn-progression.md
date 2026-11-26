# Turn progression

Create one turn per submission and call `run()` once. The SDK owns requests, tool sequencing, output, recovery, and continuation.

```swift
typealias Agent = Experimental.Agent

let turn = Agent.ChatTurn(
    input: input, router: router, host: host,
    presentation: presentation, observe: receive
)
let output = try await turn.run()
```

Supply initial messages, tools, and model in `input`; reuse the router across turns. Headless consumers can omit `presentation` and `observe`.

## Host capabilities

Implement `Agent.TurnHost`:

- `prepare`: page context and supply provider request capabilities.
- `executeTool`: apply permissions and execute the tool.
- `refreshTools`: update tool definitions and execution capabilities after a cloud batch.
- `completionRequested`: report explicit app completion; defaults to false.
- `classifyFailure`: classify request errors for recovery.

The host owns paging, native execution, permissions, persistence, and app message identity. Request services receive synchronous `reported` callbacks for terminal diagnostics, including after cancellation.

## Presentation

Implement optional `Agent.TurnPresentation` methods; all default to no-ops:

- `finishToolProse(hasProse:)`: finish prose before committing a cloud tool batch.
- `beforeTool(_:)`: finish presentation handoff before execution.
- `afterTool()`: restore feedback before admitting the result.
- `drain()`: finish displayed output before completion or recovery.

`observe` receives ordered, awaited progress updates; keep speech and animation waits in presentation methods.

## Output and cancellation

- `checkpoint()`: read saveable output while the turn continues.
- `stop()`: close output admission and return a checkpoint.
- `cancel()`: interrupt pending work; caller task cancellation is forwarded automatically.
- `propagateStreamCancellation`: choose whether stream cancellation throws or returns empty output.

Keep output-to-app identity mapping scoped to the turn. The Apple wrapper handles callback-cancellation ordering; checkpoints retain accepted partial output.

## Execution limits

A turn allows 40 requests and one shared recovery attempt for empty replies or recoverable cloud interruptions. Local inline tools return results to the same native generation.

Rust consumers use `agent::chat_turn::ChatTurn` directly. Lower-level `Agent.Round`, `Turn`, and `Output` remain available for custom orchestration.
